import Foundation
import HouseCatCore
import Observation
import os
import WatchConnectivity
import WidgetKit

/// The Watch's side of the link with the iPhone (CLAUDE.md "Watch"). What the iPhone sends goes into this
/// Watch's App Group in the widget's own layout (the snapshot, the kit's pictures), so the Watch app and its
/// complication read it with `WidgetWorld` as the widget does; Feed and Stroke go into the inbox there and to
/// the iPhone, which puts them in the save. When the iPhone's kit is not the one here, the Watch asks for its
/// pictures one by one while the iPhone is in reach, kit.json last (until they are here, the screen draws
/// symbols). On the Watch the pictures keep their kit names but hold HEIC, which the iPhone makes them.
@MainActor
@Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    fileprivate nonisolated static let log = Logger(subsystem: "com.housecatgame.housecat", category: "watch")

    /// Goes up whenever something new arrives, so the screen draws it.
    private(set) var revision = 0
    /// The kit being fetched now.
    @ObservationIgnored private var fetching: String?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// A tap to the iPhone: queued until it is in reach, and straight away when it is (it answers with the
    /// snapshot after it). The save takes each event once, so sending both ways is safe.
    func send(_ event: GameEvent) {
        let session = WCSession.default
        guard session.activationState == .activated, let data = WatchMessages.encode(event) else { return }
        session.transferUserInfo([WatchMessages.event: data])
        if session.isReachable {
            session.sendMessage([WatchMessages.event: data], replyHandler: { reply in
                Self.keep(snapshot: reply[WatchMessages.snapshot] as? Data)
            }, errorHandler: nil)
        }
    }

    /// The iPhone's kit is `key`: fetch its files unless they are here.
    fileprivate func want(kit key: String?) {
        guard let key, key != fetching else { return }
        let here = WidgetFiles.read(WidgetKitInfo.self, from: WidgetFiles.kitFile("kit.json"))?.key
        let complete = WatchMessages.kitFiles.allSatisfy { name in
            WidgetFiles.kitFile(name).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
        let session = WCSession.default
        guard here != key || !complete, session.activationState == .activated, session.isReachable else { return }
        fetching = key
        Task {
            // kit.json last: once it is here, so is everything it describes.
            let names = WatchMessages.kitFiles.filter { $0 != "kit.json" } + ["kit.json"]
            var fetched = 0
            for name in names {
                guard let data = await Self.ask(for: name, kit: key) else { break }
                Self.keep(file: data, named: name)
                fetched += 1
            }
            Self.log.info("Fetched \(fetched) of \(names.count) kit files")
            fetching = nil
        }
    }

    /// One kit file from the iPhone, or nil when it is out of reach or has another kit now.
    private nonisolated static func ask(for name: String, kit key: String) async -> Data? {
        await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            WCSession.default.sendMessage([WatchMessages.file: name, WatchMessages.kitKey: key], replyHandler: { reply in
                done.resume(returning: reply[WatchMessages.data] as? Data)
            }, errorHandler: { error in
                log.error("Couldn't fetch \(name): \(error.localizedDescription)")
                done.resume(returning: nil)
            })
        }
    }

    /// Draw again (after a tap here, or when the iPhone sent something).
    func refresh() {
        revision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The iPhone's snapshot replaces this Watch's; the taps it already has leave the inbox.
    fileprivate nonisolated static func keep(snapshot data: Data?) {
        guard let data, let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              let url = WidgetFiles.snapshot
        else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        let known = snapshot.state.lastEventAt ?? .distantPast
        WidgetInbox.remove(WidgetInbox.pending().filter { $0.at <= known })
        Task { @MainActor in PhoneLink.shared.refresh() }
    }

    /// A kit file from the iPhone, by a name the Watch expects (nothing else is kept).
    fileprivate nonisolated static func keep(file data: Data?, named name: String?) {
        guard let data, let name, WatchMessages.kitFiles.contains(name), let target = WidgetFiles.kitFile(name) else { return }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            log.error("A kit file couldn't be kept: \(error.localizedDescription)")
        }
        Task { @MainActor in PhoneLink.shared.refresh() }
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        took(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        took(context)
    }

    /// In reach again: fetch what is missing.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let key = session.receivedApplicationContext[WatchMessages.kitKey] as? String
        Task { @MainActor in PhoneLink.shared.want(kit: key) }
    }

    private nonisolated func took(_ context: [String: Any]) {
        Self.keep(snapshot: context[WatchMessages.snapshot] as? Data)
        let key = context[WatchMessages.kitKey] as? String
        Task { @MainActor in PhoneLink.shared.want(kit: key) }
    }
}
