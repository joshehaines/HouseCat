import Foundation
import HouseCatCore
import ImageIO
import os
import UniformTypeIdentifiers
import WatchConnectivity

/// The iPhone's side of the Watch app (CLAUDE.md "Watch"): after every snapshot the widget gets, the Watch gets
/// it too, with the kit's key; the Watch asks for the kit's pictures one by one whenever its own are not that
/// kit's; its Feed and Stroke come back as events and go into the save as the widget's do (each counts as the
/// day's visit, from the Watch).
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    fileprivate nonisolated static let log = Logger(subsystem: "com.housecatgame.housecat", category: "watch")

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// A paired Watch with HouseCat on it.
    private var watch: WCSession? {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return nil }
        return session
    }

    func start() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// The save's state as the widget has it, for the Watch to draw and to act on, and which kit goes with it.
    func send(_ state: HouseholdState) {
        guard let watch, let data = WatchMessages.encode(WidgetSnapshot(state: state, writtenAt: Date())) else { return }
        var context: [String: Any] = [WatchMessages.snapshot: data]
        context[WatchMessages.kitKey] = Self.kitKey
        do {
            try watch.updateApplicationContext(context)
        } catch {
            Self.log.error("The Watch's snapshot didn't go: \(error.localizedDescription)")
        }
    }

    /// A new kit (a new cat, coat or outfit): its key goes to the Watch, which then asks for the pictures.
    func sendKit() {
        send(GameSession.shared.current)
    }

    /// A Watch tap into the save; the snapshot after it, for the Watch's reply.
    fileprivate func take(_ event: GameEvent?) -> Data? {
        if let event {
            GameSession.shared.importEvents([event])
        }
        return WatchMessages.encode(WidgetSnapshot(state: GameSession.shared.current, writtenAt: Date()))
    }

    // MARK: The kit's pictures

    private nonisolated static var kitKey: String? {
        WidgetFiles.read(WidgetKitInfo.self, from: WidgetFiles.kitFile("kit.json"))?.key
    }

    /// One kit file for the Watch, if it is still this kit's: a picture made Watch-sized (HEIC keeps its
    /// transparency at a tenth of PNG's size, so each fits in one message), kit.json as it is.
    fileprivate nonisolated static func kitFile(_ name: String, key: String) -> Data? {
        guard key == kitKey, WatchMessages.kitFiles.contains(name), let url = WidgetFiles.kitFile(name) else { return nil }
        guard name.hasSuffix(".png") else { return try? Data(contentsOf: url) }
        let pixels = name.hasPrefix("icon_") ? WatchMessages.pictureIconPixels : WatchMessages.pictureCatPixels
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixels,
              ] as CFDictionary)
        else { return nil }
        for type in [UTType.heic, .png] {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                if CGImageDestinationFinalize(destination) {
                    return data as Data
                }
            }
        }
        return nil
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            WatchLink.shared.send(GameSession.shared.current)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another Watch: start again with it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// A Watch paired, or HouseCat put on it: the snapshot again.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            WatchLink.shared.send(GameSession.shared.current)
        }
    }

    /// A tap queued while the iPhone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let event = WatchMessages.event(in: userInfo) else { return }
        Task { @MainActor in
            _ = WatchLink.shared.take(event)
        }
    }

    /// While in reach: a tap goes into the save and the snapshot comes straight back; a kit file is answered
    /// with its bytes.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let name = message[WatchMessages.file] as? String, let key = message[WatchMessages.kitKey] as? String {
            replyHandler(Self.kitFile(name, key: key).map { [WatchMessages.data: $0] } ?? [:])
            return
        }
        let event = WatchMessages.event(in: message)
        let snapshot = DispatchQueue.main.sync {
            MainActor.assumeIsolated { WatchLink.shared.take(event) }
        }
        replyHandler(snapshot.map { [WatchMessages.snapshot: $0] } ?? [:])
    }
}
