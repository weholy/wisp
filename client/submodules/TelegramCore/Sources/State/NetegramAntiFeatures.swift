import Foundation
import Postbox
import NetegramStore

/// Netegram: the switches that make the client ignore instructions to destroy history.
///
/// Keys are mirrored in NetegramGhost (SettingsUI). They live in NGStore because the decision
/// is taken deep inside update processing, long before any account preference is reachable,
/// and because it describes this device rather than the account.
///
/// Reading these through NSUserDefaults was the fork's most damaging bug. This code also runs
/// in the notification service — that extension polls the difference and applies deletions
/// into the shared Postbox — and a preferences domain there belongs to the extension, not the
/// app. So anti-revoke was always off in exactly the case it exists for: a message taken back
/// while the app sat in the background. The user saw marks accumulate while using the app and
/// quietly disappear afterwards, which reads as the setting resetting itself.
enum NetegramAnti {
    static var revoke: Bool {
        return NGStore.bool(forKey: "netegram.anti.revoke")
    }

    static var edit: Bool {
        return NGStore.bool(forKey: "netegram.anti.edit")
    }

    static var autoDelete: Bool {
        return NGStore.bool(forKey: "netegram.anti.autoDelete")
    }
}

/// Netegram: true while the client ignores a chat's ban on saving and forwarding.
///
/// The restriction is advisory — the server sends the content either way and only asks the
/// client to hide the buttons, which is why lifting it needs nothing but this check.
public func netegramAllowSavingProtectedContent() -> Bool {
    return NGStore.bool(forKey: "netegram.ghost.allowSaving")
}

/// Netegram: true while the stories bar is hidden everywhere.
public func netegramHideStories() -> Bool {
    return NGStore.bool(forKey: "netegram.ghost.hideStories")
}

/// Netegram: true while a call has to be confirmed before it is placed.
public func netegramConfirmCalls() -> Bool {
    return NGStore.bool(forKey: "netegram.ghost.confirmCalls")
}

/// Netegram: true while picked audio files are sent as voice messages.
public func netegramSendAudioAsVoice() -> Bool {
    return NGStore.bool(forKey: "netegram.ghost.sendAsVoice")
}

/// Netegram: how much bigger to make download chunks. Nil while the boost is off.
///
/// A larger part means fewer round trips, which is where the speed comes from. The cost is
/// that the server starts answering with FLOOD_WAIT sooner, so this is opt-in.
public func netegramDownloadBoost() -> (partSize: Int64, parallelParts: Int)? {
    guard NGStore.bool(forKey: "netegram.ghost.fastDownload") else {
        return nil
    }
    // 1 MB is the largest part the file API accepts, and 1 MB has to stay divisible by it.
    return (1024 * 1024, 12)
}

/// Netegram: true when the fake-activity screen is aimed at this chat.
///
/// Telegram only tells a user you are typing when it believes they are online, and drops the
/// request otherwise. For a chat picked on the fake-activity screen that check defeats the
/// point — the action is there to be seen whenever they look — so it is skipped. Keys are
/// mirrored in NetegramFakeActivity (SettingsUI).
func netegramFakeActivityTargets(_ peerId: PeerId) -> Bool {
    guard NGStore.bool(forKey: "netegram.fake.activityEnabled") else {
        return false
    }
    return NGStore.stringArray(forKey: "netegram.fake.activityPeers")?.contains("\(peerId.toInt64())") ?? false
}

/// Netegram: messages someone tried to take back, kept and flagged instead of removed.
///
/// An id list rather than a change to the message itself: rewriting the text to carry a marker
/// meant editing every kept message in the database, and the marker then lived inside the
/// bubble, where it reads as part of what was written. The chat asks this list while laying a
/// message out and draws the mark beside the bubble instead.
///
/// Held in memory and mirrored to disk. It is consulted on every bubble layout, which is far
/// too often to touch the store, and it has to survive a restart or yesterday's kept messages
/// would quietly lose their mark.
///
/// Its own file rather than a settings key, for two reasons. It is appended to on every
/// incoming deletion, from whichever process applied the difference, so it is the fork's
/// hottest writer and does not belong in the same document as the switches. And it needs
/// eviction: the previous version emptied the entire list on reaching its limit, so about a
/// day into a busy account every mark in the app disappeared at once.
public enum NetegramDeletedMessages {
    private static let maximumTracked = 4000

    private static let store = NGOrderedSetStore(name: "deletedMessages", limit: UInt(NetegramDeletedMessages.maximumTracked))

    private static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    public static func insert(_ ids: [MessageId]) {
        guard !ids.isEmpty else {
            return
        }
        NetegramDeletedMessages.store.addObjects(ids.map(NetegramDeletedMessages.key))
    }

    public static func contains(_ id: MessageId) -> Bool {
        return NetegramDeletedMessages.store.containsObject(NetegramDeletedMessages.key(id))
    }

    /// Called when the app steps back, so a burst of marks recorded a moment earlier is on
    /// disk before iOS is free to terminate the process.
    public static func flush() {
        NetegramDeletedMessages.store.flush()
    }
}

/// Keeps the messages and records them as deleted, instead of removing them.
///
/// Recording alone is not enough to see anything: the chat re-lays a message out only when the
/// message itself changed, and this path deliberately leaves it untouched. So each kept message
/// is re-stored unchanged — same text, same media, same everything — purely to make the history
/// view emit an update and give the bubble a chance to draw the mark.
func netegramMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) {
    NetegramDeletedMessages.insert(ids)

    for id in ids {
        transaction.updateMessage(id, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(
                    authorId: forwardInfo.author?.id,
                    sourceId: forwardInfo.source?.id,
                    sourceMessageId: forwardInfo.sourceMessageId,
                    date: forwardInfo.date,
                    authorSignature: forwardInfo.authorSignature,
                    psaType: forwardInfo.psaType,
                    flags: forwardInfo.flags
                )
            }

            return .update(StoreMessage(
                id: currentMessage.id,
                customStableId: currentMessage.stableId,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: storeForwardInfo,
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: currentMessage.attributes,
                media: currentMessage.media
            ))
        })
    }
}

func netegramMarkMessagesDeleted(transaction: Transaction, globalIds: [Int32]) {
    netegramMarkMessagesDeleted(transaction: transaction, ids: transaction.messageIdsForGlobalIds(globalIds))
}

/// True when an edit should be discarded so the text you already read stays put.
///
/// Only incoming messages are protected: refusing your own edits would mean typing a
/// correction, watching it succeed on the server, and never seeing it apply locally.
func netegramShouldIgnoreEdit(transaction: Transaction, id: MessageId) -> Bool {
    guard NetegramAnti.edit else {
        return false
    }
    guard let message = transaction.getMessage(id) else {
        return false
    }
    return message.flags.contains(.Incoming)
}

/// Netegram: descriptions replaced with your own text, on this device only.
///
/// Nothing is sent anywhere — the person keeps whatever they wrote, and only you see the
/// replacement. Useful when someone's "about" says nothing and you need a reminder of who
/// they are.
///
/// Kept in memory and mirrored to disk for the same reason as the deleted list: it is read
/// while the profile is laid out, and it has to outlive a restart.
public enum NetegramLocalBio {
    private static let storageKey = "netegram.localBio"

    private static var cache: [String: String]?
    private static let lock = NSLock()

    /// The cache is dropped whenever the store changes under us — an import, or an edit made
    /// in another process. Without this, importing a settings file left the old descriptions
    /// on screen until the app was restarted.
    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(forName: NGStore.didChangeNotification, object: nil, queue: nil, using: { _ in
        NetegramLocalBio.lock.lock()
        NetegramLocalBio.cache = nil
        NetegramLocalBio.lock.unlock()
    })

    private static func loaded() -> [String: String] {
        if let cache = NetegramLocalBio.cache {
            return cache
        }
        _ = NetegramLocalBio.observer
        let stored = (NGStore.dictionary(forKey: NetegramLocalBio.storageKey) as? [String: String]) ?? [:]
        NetegramLocalBio.cache = stored
        return stored
    }

    private static func store(_ value: [String: String]) {
        NetegramLocalBio.cache = value
        NGStore.setObject(value, forKey: NetegramLocalBio.storageKey)
    }

    public static func set(peerId: PeerId, text: String) {
        NetegramLocalBio.lock.lock()
        var stored = NetegramLocalBio.loaded()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty replacement is a removal, not a blank description: leaving it would hide the
        // real text behind nothing with no way to tell the two apart.
        if trimmed.isEmpty {
            stored.removeValue(forKey: "\(peerId.toInt64())")
        } else {
            stored["\(peerId.toInt64())"] = trimmed
        }
        NetegramLocalBio.store(stored)
        NetegramLocalBio.lock.unlock()
    }

    public static func clear(peerId: PeerId) {
        NetegramLocalBio.set(peerId: peerId, text: "")
    }

    public static func value(peerId: PeerId) -> String? {
        NetegramLocalBio.lock.lock()
        defer { NetegramLocalBio.lock.unlock() }
        return NetegramLocalBio.loaded()["\(peerId.toInt64())"]
    }
}

/// The description to show: your replacement when there is one, otherwise what the server sent.
public func netegramDisplayBio(peerId: PeerId, about: String?) -> String? {
    return NetegramLocalBio.value(peerId: peerId) ?? about
}
