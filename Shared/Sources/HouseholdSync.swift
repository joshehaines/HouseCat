import CloudKit
import Foundation
import HouseCatCore

/// Co-owning (SPEC step 8; CLAUDE.md "Sharing mechanics"): the household's events in a CloudKit zone the owner
/// shares with a co-owner by a one-time invite link. Each phone keeps its own log and takes in the other's
/// events by id; HouseCatCore's merge makes any order give the same household (CoOwningTests), and the reducer
/// settles what two people did apart (the later placement into taken cells yields, a purchase the Beans no
/// longer cover is refused). Only events travel, never entitlements.
///
/// Off until the iCloud container is on the App ID (it needs the developer team): `HouseCatCloudKit` in
/// Info.plist is false, and CloudKit is never touched (making a CKContainer without the entitlement traps).
enum HouseholdSync {
    static let zoneName = "Household"
    static let recordType = "Event"

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HouseCatCloudKit") as? Bool == true
    }

    /// Who this phone's events are from: the owner, or the co-owner who accepted an invite.
    @MainActor static var actor: GameEvent.Actor {
        get {
            let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
            return defaults.string(forKey: "coOwner").map { .coOwner($0) } ?? .owner
        }
        set {
            let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
            if case let .coOwner(name) = newValue {
                defaults.set(name, forKey: "coOwner")
            } else {
                defaults.removeObject(forKey: "coOwner")
            }
        }
    }

    /// The running engines, once started.
    @MainActor private(set) static var engine: HouseholdSyncEngine?

    @MainActor static func start() {
        guard isEnabled, engine == nil else { return }
        engine = HouseholdSyncEngine()
    }

    /// A new event on this phone, to send.
    @MainActor static func queue(_ event: GameEvent) {
        guard let engine else { return }
        Task { await engine.queue(event) }
    }

    /// The owner's invite: a one-time link for one person (unaccepted links lapse; Tuning.Sharing).
    static func invite() async throws -> URL {
        guard isEnabled else { throw SyncError.unavailable }
        let container = CKContainer(identifier: EventStoreIdentifiers.cloudKitContainer)
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

    /// The co-owner's side: an invite accepted on this phone (the system hands the app the share's metadata).
    static func accept(_ metadata: CKShare.Metadata, as name: String) async throws {
        guard isEnabled else { throw SyncError.unavailable }
        let container = CKContainer(identifier: metadata.containerIdentifier)
        _ = try await container.accept(metadata)
        await MainActor.run {
            actor = .coOwner(name)
            engine = nil
            start()
        }
    }

    /// A friend code for an invite (Josh, 18 Oct; Finch's friend code): a record in the app's public database
    /// named by the code, holding the one-time link and when it lapses (Tuning.Coop.friendCodeHours). Anyone with
    /// the code can read it; only its maker can change it. No server of our own.
    static func friendCode(for url: URL) async throws -> String {
        guard isEnabled else { throw SyncError.unavailable }
        let database = CKContainer(identifier: EventStoreIdentifiers.cloudKitContainer).publicCloudDatabase
        var rng = SystemRandomNumberGenerator()
        // A code already taken is never overwritten: another one is drawn.
        for _ in 0 ..< 5 {
            let code = FriendCode.make(using: &rng)
            let record = CKRecord(recordType: codeRecordType, recordID: CKRecord.ID(recordName: code))
            record["url"] = url.absoluteString as CKRecordValue
            record["expires"] = Date().addingTimeInterval(Double(Tuning.Coop.friendCodeHours) * 3600) as CKRecordValue
            let saved = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            if case .success? = saved.saveResults[record.recordID] {
                return code
            }
        }
        throw SyncError.noLink
    }

    /// The invite a friend code stands for, if it has not lapsed (then the usual join screen opens).
    static func invite(forCode typed: String) async throws -> CKShare.Metadata {
        guard isEnabled else { throw SyncError.unavailable }
        guard let code = FriendCode.normalised(typed) else { throw SyncError.badCode }
        let container = CKContainer(identifier: EventStoreIdentifiers.cloudKitContainer)
        let record = try await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: code))
        guard let expires = record["expires"] as? Date, expires > Date(),
              let text = record["url"] as? String, let url = URL(string: text) else { throw SyncError.badCode }
        return try await container.shareMetadata(for: url)
    }

    static let codeRecordType = "FriendCode"

    enum SyncError: Error {
        case unavailable
        case noLink
        case badCode
    }
}

/// The CloudKit container's name (also the save's mirroring container).
enum EventStoreIdentifiers {
    static let cloudKitContainer = "iCloud.com.housecatgame.housecat"
}

/// CKSyncEngine over the household zone: the owner's in the private database, a co-owner's in the shared one.
/// Events go up as records named by their id with the event as JSON; any that come down go into the save.
actor HouseholdSyncEngine: CKSyncEngineDelegate {
    private var engine: CKSyncEngine?
    private var outbox: [CKRecord.ID: GameEvent] = [:]
    private let stateKey: String

    @MainActor init() {
        let shared = if case .coOwner = HouseholdSync.actor {
            true
        } else {
            false
        }
        stateKey = shared ? "sync.shared" : "sync.private"
        Task { await self.boot(shared: shared) }
    }

    private func boot(shared: Bool) {
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
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: HouseholdSync.zoneName))])
        }
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: HouseholdSync.zoneName)
    }

    func queue(_ event: GameEvent) {
        let id = CKRecord.ID(recordName: event.id.uuidString, zoneID: zoneID)
        outbox[id] = event
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine _: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey)
            }
        case let .fetchedRecordZoneChanges(changes):
            let events = changes.modifications.compactMap { modification -> GameEvent? in
                guard let data = modification.record["payload"] as? Data else { return nil }
                return try? JSONDecoder().decode(GameEvent.self, from: data)
            }
            guard !events.isEmpty else { return }
            await MainActor.run { GameSession.shared.importEvents(events) }
        case let .sentRecordZoneChanges(sent):
            for saved in sent.savedRecords {
                outbox[saved.recordID] = nil
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
        let outbox = outbox
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let event = outbox[id], let data = try? JSONEncoder().encode(event) else { return nil }
            let record = CKRecord(recordType: HouseholdSync.recordType, recordID: id)
            record["payload"] = data as CKRecordValue
            return record
        }
    }
}
