import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import NetegramStore

public enum NetegramFakeStrings {
    public static let title = "Фейк-активность"
    public static let subtitle = "Печатает, записывает, читает"

    public static let activityHeader = "ПОКАЗЫВАТЬ АКТИВНОСТЬ"
    public static let activityEnabled = "Включить"
    public static let activityKind = "Действие"
    public static let activityPeers = "Кому показывать"
    public static let activityPeersEmpty = "никому"
    public static let activityFooter = "Выбранные чаты видят, что вы печатаете или что-то отправляете. Работает, пока приложение открыто."

    public static let readHeader = "ЧИТАТЬ БЕЗ ОТКРЫТИЯ"
    public static let readEnabled = "Включить"
    public static let readPeers = "Чьи сообщения"
    public static let readFooter = "Сообщения из выбранных чатов сразу становятся прочитанными."

    public static let chooseTitle = "Выберите чаты"
    public static let choosePlaceholder = "Поиск"
    public static let selectedCount = "выбрано"
}

/// Netegram: the activity to broadcast into a chat you are not actually in.
///
/// Every case maps onto a `sendMessageAction` the server already understands, which is why
/// this is a plain relabelling of `PeerInputActivity` rather than anything invented — the
/// recipient sees exactly what they would see if the action were real.
public enum NetegramFakeActivityKind: String, CaseIterable {
    case typing
    case recordingVoice
    case uploadingVoice
    case recordingRound
    case uploadingRound
    case uploadingPhoto
    case uploadingVideo
    case uploadingFile
    case choosingSticker
    case playingGame

    public var title: String {
        switch self {
        case .typing:
            return "Печатает"
        case .recordingVoice:
            return "Записывает голосовое"
        case .uploadingVoice:
            return "Отправляет голосовое"
        case .recordingRound:
            return "Записывает кружок"
        case .uploadingRound:
            return "Отправляет кружок"
        case .uploadingPhoto:
            return "Отправляет фото"
        case .uploadingVideo:
            return "Отправляет видео"
        case .uploadingFile:
            return "Отправляет файл"
        case .choosingSticker:
            return "Выбирает стикер"
        case .playingGame:
            return "Играет"
        }
    }

    /// Progress is reported as 0: the action never completes, because there is nothing behind
    /// it. A recipient sees the label, not the number.
    public var activity: PeerInputActivity {
        switch self {
        case .typing:
            return .typingText
        case .recordingVoice:
            return .recordingVoice
        case .uploadingVoice:
            return .uploadingFile(progress: 0)
        case .recordingRound:
            return .recordingInstantVideo
        case .uploadingRound:
            return .uploadingInstantVideo(progress: 0)
        case .uploadingPhoto:
            return .uploadingPhoto(progress: 0)
        case .uploadingVideo:
            return .uploadingVideo(progress: 0)
        case .uploadingFile:
            return .uploadingFile(progress: 0)
        case .choosingSticker:
            return .choosingSticker
        case .playingGame:
            return .playingGame
        }
    }
}

public struct NetegramFakeSettings: Equatable {
    public let activityEnabled: Bool
    public let kind: NetegramFakeActivityKind
    public let activityPeers: [Int64]
    public let readEnabled: Bool
    public let readPeers: [Int64]

    public init(activityEnabled: Bool, kind: NetegramFakeActivityKind, activityPeers: [Int64], readEnabled: Bool, readPeers: [Int64]) {
        self.activityEnabled = activityEnabled
        self.kind = kind
        self.activityPeers = activityPeers
        self.readEnabled = readEnabled
        self.readPeers = readPeers
    }
}

private let fakeActivityEnabledKey = "netegram.fake.activityEnabled"
private let fakeActivityKindKey = "netegram.fake.activityKind"
private let fakeActivityPeersKey = "netegram.fake.activityPeers"
private let fakeReadEnabledKey = "netegram.fake.readEnabled"
private let fakeReadPeersKey = "netegram.fake.readPeers"
/// The same chats as bare Telegram ids, the form MTProtoKit sees in a request. Mirrored in
/// MTNetegramGhost, which lets these through when ghost mode would otherwise hide them.
private let fakeActivityRawIdsKey = "netegram.fake.activityRawIds"
private let fakeReadRawIdsKey = "netegram.fake.readRawIds"

/// Peer ids are stored as decimal strings rather than numbers: they are full 64-bit values,
/// and JSON's number type is a double, which silently rounds anything past 2^53.
private func netegramDecodePeerIds(_ key: String) -> [Int64] {
    return (NGStore.stringArray(forKey: key) ?? []).compactMap(Int64.init)
}

private func netegramEncodePeerIds(_ values: [Int64], forKey key: String) {
    NGStore.setObject(values.map { "\($0)" }, forKey: key)
}

/// A peer id packs the chat kind in with the number; a request carries only the number.
private func netegramEncodeRawIds(_ values: [Int64], forKey key: String) {
    NGStore.setObject(values.map { "\(PeerId($0).id._internalGetInt64Value())" }, forKey: key)
}

public final class NetegramFakePreferences {
    public static let shared = NetegramFakePreferences()

    private let promise: ValuePromise<NetegramFakeSettings>

    private init() {
        self.promise = ValuePromise(NetegramFakePreferences.current(), ignoreRepeated: true)
    }

    public static func current() -> NetegramFakeSettings {
        let kind = NGStore.string(forKey: fakeActivityKindKey).flatMap(NetegramFakeActivityKind.init(rawValue:)) ?? .typing
        return NetegramFakeSettings(
            activityEnabled: NGStore.bool(forKey: fakeActivityEnabledKey),
            kind: kind,
            activityPeers: netegramDecodePeerIds(fakeActivityPeersKey),
            readEnabled: NGStore.bool(forKey: fakeReadEnabledKey),
            readPeers: netegramDecodePeerIds(fakeReadPeersKey)
        )
    }

    public var signal: Signal<NetegramFakeSettings, NoError> {
        return self.promise.get()
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.promise.set(NetegramFakePreferences.current())
    }

    public func setActivityEnabled(_ value: Bool) {
        NGStore.setObject(value, forKey: fakeActivityEnabledKey)
        self.republish()
    }

    public func setActivityKind(_ value: NetegramFakeActivityKind) {
        NGStore.setObject(value.rawValue, forKey: fakeActivityKindKey)
        self.republish()
    }

    public func setActivityPeers(_ value: [Int64]) {
        netegramEncodePeerIds(value, forKey: fakeActivityPeersKey)
        netegramEncodeRawIds(value, forKey: fakeActivityRawIdsKey)
        self.republish()
    }

    public func setReadEnabled(_ value: Bool) {
        NGStore.setObject(value, forKey: fakeReadEnabledKey)
        self.republish()
    }

    public func setReadPeers(_ value: [Int64]) {
        netegramEncodePeerIds(value, forKey: fakeReadPeersKey)
        netegramEncodeRawIds(value, forKey: fakeReadRawIdsKey)
        self.republish()
    }
}

/// Netegram: keeps the fake activity going, and the chosen chats read.
///
/// Driven by a signal rather than a timer of its own: `acquireLocalInputActivity` hands back a
/// disposable that Telegram's own activity manager keeps alive, re-sending `messages.setTyping`
/// on the cadence the server expects. Holding the disposable is the whole mechanism — dropping
/// it stops the action, and there is no separate "stop" call to get wrong.
///
/// Only one activity kind at a time, on purpose: the server takes one action per chat, and a
/// screen that let you pick several would be promising something the protocol cannot carry.
public final class NetegramFakeActivityManager {
    public static let shared = NetegramFakeActivityManager()

    private var context: AccountContext?
    private var settingsDisposable: Disposable?
    private var readDisposable: Disposable?

    /// One per chat currently being lied to. Keyed by peer id so a change to the list only
    /// disturbs the chats that actually changed.
    private var activityDisposables: [PeerId: Disposable] = [:]
    private var currentKind: NetegramFakeActivityKind?

    /// The furthest point each chat has already been read up to by this feature.
    private var appliedReadIndices: [PeerId: MessageIndex] = [:]

    private init() {
    }

    /// Called once the account is up. Safe to call again — a second account replaces the first.
    public func setContext(_ context: AccountContext) {
        self.context = context

        self.settingsDisposable?.dispose()
        self.stopEverything()

        self.settingsDisposable = (NetegramFakePreferences.shared.signal
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.apply(settings)
        })
    }

    private func stopEverything() {
        for (_, disposable) in self.activityDisposables {
            disposable.dispose()
        }
        self.activityDisposables.removeAll()
        self.currentKind = nil

        self.readDisposable?.dispose()
        self.readDisposable = nil
        self.appliedReadIndices.removeAll()
    }

    private func apply(_ settings: NetegramFakeSettings) {
        // Lists chosen before the bare ids existed get them here. A write that changes nothing
        // is ignored by the store, so once they are in place this costs nothing.
        netegramEncodeRawIds(settings.activityPeers, forKey: fakeActivityRawIdsKey)
        netegramEncodeRawIds(settings.readPeers, forKey: fakeReadRawIdsKey)

        guard let context = self.context else {
            return
        }

        self.applyActivity(settings, context: context)
        self.applyRead(settings, context: context)
    }

    private func applyActivity(_ settings: NetegramFakeSettings, context: AccountContext) {
        // Changing the action means every chat has to be re-acquired with the new one; there
        // is no way to amend an activity in place.
        if self.currentKind != settings.kind {
            for (_, disposable) in self.activityDisposables {
                disposable.dispose()
            }
            self.activityDisposables.removeAll()
            self.currentKind = settings.kind
        }

        let wanted: Set<PeerId> = settings.activityEnabled ? Set(settings.activityPeers.map { PeerId($0) }) : Set()

        // Keys collected first: dropping entries while iterating the dictionary they came from
        // works only by accident of value semantics, and reads as a bug either way.
        for peerId in self.activityDisposables.keys.filter({ !wanted.contains($0) }) {
            self.activityDisposables[peerId]?.dispose()
            self.activityDisposables.removeValue(forKey: peerId)
        }

        for peerId in wanted where self.activityDisposables[peerId] == nil {
            let space = PeerActivitySpace(peerId: peerId, category: .global)
            self.activityDisposables[peerId] = context.account.acquireLocalInputActivity(peerId: space, activity: settings.kind.activity)
        }
    }

    /// Watches the chat list and reads whatever lands in the chosen chats.
    ///
    /// The chat list rather than a per-chat history view: it already carries the last message
    /// and the unread counters for every chat at once, so this needs one subscription instead
    /// of one per selected peer, and it updates the moment something arrives.
    private func applyRead(_ settings: NetegramFakeSettings, context: AccountContext) {
        self.readDisposable?.dispose()
        self.readDisposable = nil

        let peerIds = Set(settings.readPeers.map { PeerId($0) })
        guard settings.readEnabled, !peerIds.isEmpty else {
            return
        }

        self.readDisposable = (context.engine.messages.chatList(group: .root, count: 200)
        |> deliverOnMainQueue).start(next: { [weak self] chatList in
            guard let self else {
                return
            }
            for item in chatList.items {
                let peerId = item.renderedPeer.peerId
                guard peerIds.contains(peerId) else {
                    continue
                }
                guard let readCounters = item.readCounters, readCounters.isUnread else {
                    continue
                }
                // An album arrives as several messages in one item, and the order is not
                // promised — the newest is the one to read up to.
                guard let message = item.messages.max(by: { $0.index < $1.index }) else {
                    continue
                }
                let index = MessageIndex(id: message.id, timestamp: message.timestamp)
                // The chat list emits again on every change, and the unread counter does not
                // clear the instant the read is sent, so without this the same message is read
                // over and over for as long as it takes the server to answer.
                if let applied = self.appliedReadIndices[peerId], applied >= index {
                    continue
                }
                self.appliedReadIndices[peerId] = index
                let _ = context.engine.messages.applyMaxReadIndexInteractively(index: index).start()
            }
        })
    }
}
