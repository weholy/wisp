import Foundation
import Postbox
import NetegramStore

/// Netegram: previous versions of edited messages, remembered by this client.
///
/// Telegram's API has no notion of edit history — the server sends the new text and a flag
/// saying the message was edited, and nothing else. The only way to know what a message used
/// to say is to have seen it before the edit arrived. So this records the old text at the
/// moment an edit is applied, and can only ever show edits this device was running for.
public struct NetegramEditVersion: Codable, Equatable {
    public let text: String
    /// When this version stopped being current, i.e. when the edit replacing it arrived.
    public let replacedAt: Int32

    public init(text: String, replacedAt: Int32) {
        self.text = text
        self.replacedAt = replacedAt
    }
}

private let editHistoryKey = "netegram.editHistory"
/// Kept small on purpose. This is a convenience for reading back a message someone just
/// reworded, not an archive — an unbounded store would grow for the life of the install.
private let maximumTrackedMessages = 300
private let maximumVersionsPerMessage = 10

public enum NetegramEditHistory {
    /// Its own file in the shared container, not a settings key.
    ///
    /// Written whenever an incoming edit is applied, which happens in the notification service
    /// as well as the app, so it has to be somewhere both processes can reach. Keeping it out
    /// of the settings document also means a stream of edits does not rewrite the switches.
    private static let lock = NSLock()
    private static var cache: [String: [NetegramEditVersion]]?

    private static var fileUrl: URL? {
        guard let directory = NGStore.storageDirectory() else {
            return nil
        }
        return URL(fileURLWithPath: directory).appendingPathComponent("editHistory.json")
    }

    /// Stable across launches, unlike the message's own stable id.
    private static func storageKey(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    /// Call with the lock held.
    private static func load() -> [String: [NetegramEditVersion]] {
        if let cache = NetegramEditHistory.cache {
            return cache
        }

        var loaded: [String: [NetegramEditVersion]] = [:]
        if let fileUrl = NetegramEditHistory.fileUrl, let data = try? Data(contentsOf: fileUrl) {
            loaded = (try? JSONDecoder().decode([String: [NetegramEditVersion]].self, from: data)) ?? [:]
        }
        // Anything recorded before this moved out of the preferences domain. Read once so an
        // update does not look like the history was wiped; it is rewritten to the file below.
        if loaded.isEmpty, let legacy = UserDefaults.standard.data(forKey: editHistoryKey) {
            loaded = (try? JSONDecoder().decode([String: [NetegramEditVersion]].self, from: legacy)) ?? [:]
            if !loaded.isEmpty {
                NetegramEditHistory.write(loaded)
            }
        }

        NetegramEditHistory.cache = loaded
        return loaded
    }

    /// Call with the lock held.
    private static func save(_ value: [String: [NetegramEditVersion]]) {
        NetegramEditHistory.cache = value
        NetegramEditHistory.write(value)
    }

    private static func write(_ value: [String: [NetegramEditVersion]]) {
        guard let fileUrl = NetegramEditHistory.fileUrl, let data = try? JSONEncoder().encode(value) else {
            return
        }
        try? data.write(to: fileUrl, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Records the text a message had before the edit that is about to be applied.
    ///
    /// Does nothing when the text is unchanged: an edit can also arrive for a reaction, a pin
    /// or a media change, and recording those would fill the history with identical entries.
    public static func record(id: MessageId, previousText: String, newText: String, timestamp: Int32) {
        guard previousText != newText, !previousText.isEmpty else {
            return
        }

        NetegramEditHistory.lock.lock()
        defer { NetegramEditHistory.lock.unlock() }

        var storage = self.load()
        let key = self.storageKey(id)

        var versions = storage[key] ?? []
        // The first edit also has to record the original, which is the text being replaced.
        versions.append(NetegramEditVersion(text: previousText, replacedAt: timestamp))
        if versions.count > maximumVersionsPerMessage {
            versions.removeFirst(versions.count - maximumVersionsPerMessage)
        }
        storage[key] = versions

        if storage.count > maximumTrackedMessages {
            // Drop whichever entries were touched longest ago. Sorting by the newest version
            // in each entry keeps the messages still being edited, which are the ones worth
            // being able to look back at.
            let ordered = storage.sorted(by: { lhs, rhs in
                (lhs.value.last?.replacedAt ?? 0) > (rhs.value.last?.replacedAt ?? 0)
            })
            storage = Dictionary(uniqueKeysWithValues: ordered.prefix(maximumTrackedMessages).map { ($0.key, $0.value) })
        }

        self.save(storage)
    }

    /// Oldest first. Empty when this device never saw the message change.
    public static func versions(id: MessageId) -> [NetegramEditVersion] {
        NetegramEditHistory.lock.lock()
        defer { NetegramEditHistory.lock.unlock() }

        return self.load()[self.storageKey(id)] ?? []
    }
}
