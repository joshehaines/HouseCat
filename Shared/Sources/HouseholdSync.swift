import CloudKit
import Foundation
import HouseCatCore
import HouseCatGame

extension Notification.Name {
    /// This phone now holds another household (it joined someone's cat, left it, or was removed): the app goes
    /// back to its first screen for the cat now in the save. `userInfo["notice"]` says what happened, if anything.
    static let houseCatSwitched = Notification.Name("houseCatSwitched")
}

/// Co-owning (SPEC step 8; CLAUDE.md "Sharing mechanics", "Leaving and removing"): the household's events in a
/// CloudKit zone the owner shares with a co-owner by a one-time invite link. Each phone keeps its own log and
/// takes in the other's events by id; HouseCatCore's merge makes any order give the same household
/// (CoOwningTests), and the reducer settles what two people did apart (the later placement into taken cells
/// yields, a purchase the Beans no longer cover is refused). Only events travel, never entitlements.
///
/// Who looks after the cat is in the save too (`coOwnerJoined`, `coOwnerLeft`, `coOwnerRemoved`;
/// MembershipTests): the owner stops sharing, a co-owner leaves and gets back the cat set aside on their phone
/// when they joined.
///
/// Off until the iCloud container is on the App ID (it needs the developer team): `HouseCatCloudKit` in
/// Info.plist is false, and CloudKit is never touched (making a CKContainer without the entitlement traps).
enum HouseholdSync {
    static let zoneName = "Household"
    static let recordType = "Event"
    static let codeRecordType = "FriendCode"

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HouseCatCloudKit") as? Bool == true
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    }

    private static var container: CKContainer {
        CKContainer(identifier: EventStoreIdentifiers.cloudKitContainer)
    }

    /// The household's zone in the owner's private database.
    static var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName)
    }

    /// Who this phone's events are from: the owner, or the co-owner who accepted an invite.
    @MainActor static var actor: GameEvent.Actor {
        get {
            defaults.string(forKey: "coOwner").map { .coOwner($0) } ?? .owner
        }
        set {
            if case let .coOwner(name) = newValue {
                defaults.set(name, forKey: "coOwner")
            } else {
                defaults.removeObject(forKey: "coOwner")
            }
        }
    }

    /// Whether this phone looks after someone else's cat.
    @MainActor static var isCoOwner: Bool {
        if case .coOwner = actor { true } else { false }
    }

    /// On a co-owner's phone, the shared household's zone: the owner's zone, named for them in CloudKit.
    @MainActor static var sharedZoneID: CKRecordZone.ID? {
        defaults.string(forKey: "coOwner.zoneOwner").map { CKRecordZone.ID(zoneName: zoneName, ownerName: $0) }
    }

    /// Members this phone chose not to see (Hide, in the Together card): their name shows as the cat's other
    /// owner, and their paw prints and presents are not announced. A device preference, like what was last seen.
    @MainActor static var hidden: Set<String> {
        get { Set(defaults.stringArray(forKey: "together.hidden") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "together.hidden") }
    }

    /// The running engine, once started.
    @MainActor private(set) static var engine: HouseholdSyncEngine?

    @MainActor static func start() {
        guard isEnabled, engine == nil else { return }
        engine = HouseholdSyncEngine()
        if !isCoOwner {
            Task { await settleMembers() }
        }
    }

    /// A new event on this phone, to send.
    @MainActor static func queue(_ event: GameEvent) {
        guard let engine else { return }
        Task { await engine.queue(event.id) }
    }

    // MARK: Inviting and joining

    /// The owner's invite: a one-time link for one person (unaccepted links lapse; Tuning.Sharing).
    static func invite() async throws -> URL {
        guard isEnabled else { throw SyncError.unavailable }
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: zoneName)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        let share: CKShare
        if let existing = try? await database.record(for: CKRecord.ID(
            recordName: CKRecordNameZoneWideShare,
            zoneID: zone.zoneID
        )) as? CKShare {
            share = existing
        } else {
            share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = "A cat to share" as CKRecordValue
            share.publicPermission = .none
        }
        let participant = CKShare.Participant.oneTimeURLParticipant()
        participant.permission = .readWrite
        share.addParticipant(participant)
        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        guard case let .success(record)? = saved.saveResults[share.recordID], let savedShare = record as? CKShare,
              let id = savedShare.participants.first(where: { $0.acceptanceStatus == .pending && $0.userIdentity.lookupInfo == nil })?
                  .participantID,
              let url = savedShare.oneTimeURL(for: id)
        else { throw SyncError.noLink }
        return url
    }

    /// Why this phone can't take an invite now, if it can't: one household at a time.
    @MainActor static var joinBlocked: String? {
        if isCoOwner {
            return "You already share someone's cat. Leave it first (in its Together card), then open this invite again."
        }
        let session = GameSession.shared
        if session.isCoOwned {
            let name = session.cat?.name ?? "your cat"
            return "You share \(name) with someone. Stop sharing \(name) first, then open this invite again."
        }
        return nil
    }

    /// The co-owner's side: an invite accepted on this phone (the system hands the app the share's metadata). The
    /// household is fetched before the switch, so the cat is there when the room opens.
    static func accept(_ metadata: CKShare.Metadata, as name: String) async throws {
        guard isEnabled else { throw SyncError.unavailable }
        guard await joinBlocked == nil else { throw SyncError.alreadySharing }
        let container = CKContainer(identifier: metadata.containerIdentifier)
        _ = try await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        // The zone can take a moment to appear in the shared database after accepting.
        var fetched: [GameEvent]?
        for attempt in 0 ..< 3 where fetched == nil {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(2))
            }
            fetched = try? await fetchEvents(in: zoneID, database: container.sharedCloudDatabase)
        }
        guard let events = fetched, !events.isEmpty else { throw SyncError.noHousehold }
        await MainActor.run {
            defaults.set(zoneID.ownerName, forKey: "coOwner.zoneOwner")
            switchToShared(events, as: name)
        }
    }

    /// The local half of joining: this phone's own cat is set aside, the save becomes the shared household, this
    /// phone becomes the co-owner `name`, and its first event says so (it reaches the owner with the next sync).
    @MainActor static func switchToShared(_ events: [GameEvent], as name: String) {
        engine = nil
        UserDefaults.standard.removeObject(forKey: HouseholdSyncEngine.sharedStateKey)
        do {
            try GameSession.shared.joinShared(events)
        } catch {
            NSLog("HouseCat: setting this device's own cat aside failed: %@", "\(error)")
            return
        }
        actor = .coOwner(name)
        // Who was hidden belonged to the household this device had.
        hidden = []
        start()
        let session = GameSession.shared
        session.append(.coOwnerJoined, at: session.now())
        NotificationCenter.default.post(name: .houseCatSwitched, object: nil)
    }

    #if DEBUG
        /// HOUSECAT_SCREEN=join: someone else's cat to join (Mochi, a ginger tabby with five days behind her), so
        /// joining, the cat set aside and leaving can be tried with CloudKit off.
        @MainActor static func debugJoin(as name: String) {
            let clock = DayClock()
            let start = Date().addingTimeInterval(-5 * 86400)
            var log = SaveLog()
            func add(_ kind: GameEvent.Kind, _ date: Date) {
                let at = log.timestamp(for: date)
                log.append(GameEvent(at: at, day: clock.day(of: at), kind: kind))
            }
            add(.householdCreated(seed: 0xC0_0517, clock: clock), start)
            add(.catAdopted(catID: GameSession.catID, name: "Mochi", personality: .aloof, isKitten: false), start)
            if let look = GameWorld.catArt?.builder.preset("ginger_tabby")?.look {
                add(.catLookSet(catID: GameSession.catID, look: look), start)
            }
            if let layout = try? GameWorld.art?.data("rooms/layout_living_demo.json", as: RoomModel.self) {
                for item in layout.items {
                    add(.itemGranted(itemID: item.id), start)
                    let facing: GameEvent.Facing = item.facing == "L" ? .left : .right
                    add(.itemPlaced(itemID: item.id, room: .living, x: Int(item.u.rounded()), y: Int(item.v.rounded()), facing: facing), start)
                }
            }
            for day in 0 ..< 5 {
                let morning = start.addingTimeInterval(Double(day) * 86400 + 3600)
                add(.arrived, morning)
                add(.fed(catID: GameSession.catID), morning.addingTimeInterval(60))
            }
            switchToShared(log.events, as: name)
        }
    #endif

    /// Every event in a shared zone, as it is now.
    private static func fetchEvents(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [GameEvent] {
        var events: [GameEvent] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for case let .success(modification) in changes.modificationResultsByID.values {
                if let event = HouseholdSyncEngine.event(in: modification.record) {
                    events.append(event)
                }
            }
            token = changes.changeToken
            more = changes.moreComing
        }
        return events
    }

    // MARK: Stopping and leaving

    /// The owner stops sharing: each co-owner is taken out (`coOwnerRemoved`, so the household's history says
    /// so), then the share is deleted with any invite links still waiting, and the friend code. The cat, the home,
    /// the streak and the Beans stay; the visits already made still count.
    @MainActor static func stopSharing() async {
        guard !isCoOwner else { return }
        let session = GameSession.shared
        for key in session.state(at: session.now()).coOwners {
            session.append(.coOwnerRemoved(key: key), at: session.now())
        }
        await engine?.sendNow()
        guard isEnabled else { return }
        let share = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        _ = try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [share])
        await deleteFriendCode()
    }

    /// A co-owner leaves: the household hears it (`coOwnerLeft`), this phone leaves the share, and the cat set
    /// aside when they joined comes back (or the intro starts a new one). The shared cat stays with its owner.
    @MainActor static func leave() async {
        guard isCoOwner else { return }
        let session = GameSession.shared
        let cat = session.cat?.name ?? "the cat"
        session.append(.coOwnerLeft, at: session.now())
        await engine?.sendNow()
        let zone = sharedZoneID
        engine = nil
        await leaveShare(zone)
        returnHome(notice: "You've left \(cat)'s home.")
    }

    /// On a co-owner's phone: the owner stopped sharing or took them out (the shared zone went, or the owner's
    /// `coOwnerRemoved` came down).
    @MainActor static func removed() {
        guard isCoOwner else { return }
        let cat = GameSession.shared.cat?.name ?? "The cat"
        engine = nil
        returnHome(notice: "\(cat)'s owner stopped sharing \(cat) with you.")
    }

    /// After an import on a co-owner's phone: still in the household?
    @MainActor static func checkMembership() {
        guard isCoOwner else { return }
        let session = GameSession.shared
        if session.state(at: session.now()).formerOwners.contains(actor.key) {
            removed()
        }
    }

    /// Deleting the shared zone from the shared database takes this person out of the share; the owner's zone
    /// and its events are untouched.
    private static func leaveShare(_ zone: CKRecordZone.ID?) async {
        guard isEnabled, let zone else { return }
        _ = try? await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zone])
    }

    /// Back to this phone's own household, as its owner; `notice` says why, and the card adds what came back.
    @MainActor private static func returnHome(notice: String) {
        guard isCoOwner else { return }
        engine = nil
        actor = .owner
        hidden = []
        defaults.removeObject(forKey: "coOwner.zoneOwner")
        UserDefaults.standard.removeObject(forKey: HouseholdSyncEngine.sharedStateKey)
        let restored = GameSession.shared.returnToOwnHousehold()
        start()
        let next = restored.map { "\($0) is back." } ?? "You can adopt a cat of your own."
        NotificationCenter.default.post(name: .houseCatSwitched, object: nil, userInfo: ["notice": "\(notice) \(next)"])
    }

    /// On the owner's phone: co-owners who left the share while their `coOwnerLeft` could not reach the household
    /// (offline, or the app deleted) are recorded as gone once the share has nobody in it but the owner. A share
    /// that can't be read (no network) changes nothing.
    @MainActor static func settleMembers() async {
        guard isEnabled, !isCoOwner else { return }
        let session = GameSession.shared
        let coOwners = session.state(at: session.now()).coOwners
        guard !coOwners.isEmpty else { return }
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        let joined: Int
        do {
            let share = try await container.privateCloudDatabase.record(for: id) as? CKShare
            joined = share?.participants.count(where: { $0.role != .owner && $0.acceptanceStatus == .accepted }) ?? 0
        } catch let error as CKError where error.code == .unknownItem {
            joined = 0
        } catch {
            return
        }
        guard joined == 0 else { return }
        for key in coOwners {
            session.append(.coOwnerRemoved(key: key), at: session.now())
        }
    }

    // MARK: Friend codes

    /// A friend code for an invite (Josh, 18 Oct; Finch's friend code): a record in the app's public database
    /// named by the code, holding the one-time link and when it lapses (Tuning.Coop.friendCodeHours). Anyone with
    /// the code can read it; only its maker can change it. No server of our own.
    static func friendCode(for url: URL) async throws -> String {
        guard isEnabled else { throw SyncError.unavailable }
        let database = container.publicCloudDatabase
        var rng = SystemRandomNumberGenerator()
        // A code already taken is never overwritten: another one is drawn.
        for _ in 0 ..< 5 {
            let code = FriendCode.make(using: &rng)
            let record = CKRecord(recordType: codeRecordType, recordID: CKRecord.ID(recordName: code))
            record["url"] = url.absoluteString as CKRecordValue
            record["expires"] = Date().addingTimeInterval(Double(Tuning.Coop.friendCodeHours) * 3600) as CKRecordValue
            let saved = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            if case .success? = saved.saveResults[record.recordID] {
                defaults.set(code, forKey: "friendCode")
                return code
            }
        }
        throw SyncError.noLink
    }

    /// The invite a friend code stands for, if it has not lapsed (then the usual join screen opens).
    static func invite(forCode typed: String) async throws -> CKShare.Metadata {
        guard isEnabled else { throw SyncError.unavailable }
        guard let code = FriendCode.normalised(typed) else { throw SyncError.badCode }
        let record = try await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: code))
        guard let expires = record["expires"] as? Date, expires > Date(),
              let text = record["url"] as? String, let url = URL(string: text) else { throw SyncError.badCode }
        return try await container.shareMetadata(for: url)
    }

    /// The last friend code this phone made, from the public database (only its maker can delete it).
    private static func deleteFriendCode() async {
        guard isEnabled, let code = defaults.string(forKey: "friendCode") else { return }
        _ = try? await container.publicCloudDatabase.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: code)])
        defaults.removeObject(forKey: "friendCode")
    }

    // MARK: Your data

    /// What "Delete all my data" does in iCloud: a co-owner first leaves the share they joined (the household
    /// hears `coOwnerLeft`; the shared cat stays with its owner), then this person's own household zone goes
    /// (with it their share, if they shared their cat, and every synced event), and their friend code. Does
    /// nothing while CloudKit is off.
    static func deleteHousehold() async {
        guard isEnabled else { return }
        if await isCoOwner {
            let zone = await MainActor.run {
                let session = GameSession.shared
                session.append(.coOwnerLeft, at: session.now())
                return sharedZoneID
            }
            await engine?.sendNow()
            await MainActor.run { engine = nil }
            await leaveShare(zone)
        }
        _ = try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [ownZoneID])
        await deleteFriendCode()
        await MainActor.run {
            actor = .owner
            engine = nil
            defaults.removeObject(forKey: "coOwner.zoneOwner")
        }
    }

    enum SyncError: Error {
        case unavailable
        case noLink
        case badCode
        case alreadySharing
        case noHousehold
    }
}

/// The CloudKit container's name (also the save's mirroring container).
enum EventStoreIdentifiers {
    static let cloudKitContainer = "iCloud.com.housecatgame.housecat"
}

/// CKSyncEngine over the household zone: the owner's in the private database, a co-owner's in the shared one.
/// Events go up as records named by their id with the event as JSON; any that come down go into the save. The
/// first time an owner's engine runs, the whole save goes up (the events from before sharing was switched on).
actor HouseholdSyncEngine: CKSyncEngineDelegate {
    static let privateStateKey = "sync.private"
    static let sharedStateKey = "sync.shared"
    private static let uploadedKey = "sync.private.uploaded"

    private var engine: CKSyncEngine?
    /// Events queued before the engine was up.
    private var waiting: [UUID] = []
    private let shared: Bool
    private let zoneID: CKRecordZone.ID
    private let stateKey: String

    @MainActor init() {
        let shared = HouseholdSync.isCoOwner
        self.shared = shared
        zoneID = shared ? (HouseholdSync.sharedZoneID ?? HouseholdSync.ownZoneID) : HouseholdSync.ownZoneID
        stateKey = shared ? Self.sharedStateKey : Self.privateStateKey
        let backlog = shared || UserDefaults.standard.bool(forKey: Self.uploadedKey) ? [] : GameSession.shared.log.events.map(\.id)
        Task { await self.boot(backlog: backlog) }
    }

    private func boot(backlog: [UUID]) {
        let container = CKContainer(identifier: EventStoreIdentifiers.cloudKitContainer)
        let saved = (UserDefaults.standard.data(forKey: stateKey)).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let configuration = CKSyncEngine.Configuration(
            database: shared ? container.sharedCloudDatabase : container.privateCloudDatabase,
            stateSerialization: saved,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !shared {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        let ids = backlog + waiting
        waiting = []
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID)) })
        if !backlog.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.uploadedKey)
        }
    }

    func queue(_ id: UUID) {
        guard let engine else {
            waiting.append(id)
            return
        }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))])
    }

    /// Sends what is waiting now (before leaving, so the household hears it).
    func sendNow() async {
        try? await engine?.sendChanges()
    }

    static func event(in record: CKRecord) -> GameEvent? {
        guard record.recordType == HouseholdSync.recordType, let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(GameEvent.self, from: data)
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine _: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey)
            }
        case let .fetchedDatabaseChanges(changes):
            // On a co-owner's phone the household's zone going means the owner stopped sharing or took them out.
            guard shared, changes.deletions.contains(where: { $0.zoneID == zoneID }) else { break }
            await MainActor.run { HouseholdSync.removed() }
        case let .fetchedRecordZoneChanges(changes):
            let zoneID = zoneID
            let events = changes.modifications.filter { $0.record.recordID.zoneID == zoneID }.compactMap { Self.event(in: $0.record) }
            guard !events.isEmpty else { return }
            await MainActor.run {
                GameSession.shared.importEvents(events, fromCloud: true)
                HouseholdSync.checkMembership()
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine
        .RecordZoneChangeBatch?
    {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let uuid = UUID(uuidString: id.recordName),
                  let event = await MainActor.run(body: { GameSession.shared.event(uuid) }),
                  let data = try? JSONEncoder().encode(event) else { return nil }
            let record = CKRecord(recordType: HouseholdSync.recordType, recordID: id)
            record["payload"] = data as CKRecordValue
            return record
        }
    }
}
