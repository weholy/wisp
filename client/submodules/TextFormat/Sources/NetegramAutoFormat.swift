import Foundation
import UIKit
import TelegramCore
import NetegramStore

/// Netegram: the character styles a message can be typed in.
///
/// Telegram's block-level formatting — quotes and code blocks — is deliberately not here.
/// Those carry a paragraph attribute with a payload rather than a plain on/off flag, they
/// change the shape of the bubble rather than the letters, and a whole conversation written
/// inside a quote block is not what "always type in bold" means.
public enum NetegramTextStyle: String, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case monospace
    case spoiler

    /// The composer attribute this style writes. All six are plain flags.
    public var inputAttribute: NSAttributedString.Key {
        switch self {
        case .bold:
            return ChatTextInputAttributes.bold
        case .italic:
            return ChatTextInputAttributes.italic
        case .underline:
            return ChatTextInputAttributes.underline
        case .strikethrough:
            return ChatTextInputAttributes.strikethrough
        case .monospace:
            return ChatTextInputAttributes.monospace
        case .spoiler:
            return ChatTextInputAttributes.spoiler
        }
    }

    /// The entity the same style becomes in a sent message.
    public var entityType: MessageTextEntityType {
        switch self {
        case .bold:
            return .Bold
        case .italic:
            return .Italic
        case .underline:
            return .Underline
        case .strikethrough:
            return .Strikethrough
        case .monospace:
            return .Code
        case .spoiler:
            return .Spoiler
        }
    }

    public var title: String {
        switch self {
        case .bold:
            return "Жирный"
        case .italic:
            return "Курсив"
        case .underline:
            return "Подчёркнутый"
        case .strikethrough:
            return "Зачёркнутый"
        case .monospace:
            return "Моноширинный"
        case .spoiler:
            return "Спойлер"
        }
    }
}

/// Netegram: the one style every message goes out in.
///
/// One style, not a set. Choosing a second switches the first off, which is what the screen
/// promises and what keeps the result predictable: bold-plus-strikethrough-plus-spoiler reads
/// as a mistake, not a preference.
///
/// Applied in two places, because neither alone is enough. The composer shows it — every
/// refresh of the input puts the whole text in the style, so what you see while writing is
/// what arrives. And sending enforces it — the composer has more than one backend and text
/// can arrive by paste, autocorrect or a draft, so the outgoing message is styled again on
/// the way out regardless of how its text got there.
///
/// Cached in memory: the composer reads this on every keystroke.
public enum NetegramAutoFormat {
    private static let storageKey = "netegram.autoFormat.style"
    /// The multi-select version stored an array here. Read once so an update keeps the
    /// first style the user had picked instead of silently switching the feature off.
    private static let legacyStorageKey = "netegram.autoFormat.styles"

    private static let lock = NSLock()
    /// `.none` means not loaded yet; `.some(nil)` means loaded and switched off.
    private static var cache: NetegramTextStyle??

    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(forName: NGStore.didChangeNotification, object: nil, queue: nil, using: { _ in
        NetegramAutoFormat.lock.lock()
        NetegramAutoFormat.cache = nil
        NetegramAutoFormat.lock.unlock()
    })

    /// The style currently chosen, or nil while auto-format is off.
    public static var style: NetegramTextStyle? {
        NetegramAutoFormat.lock.lock()
        defer { NetegramAutoFormat.lock.unlock() }

        if let cached = NetegramAutoFormat.cache {
            return cached
        }
        _ = NetegramAutoFormat.observer

        let resolved: NetegramTextStyle?
        if let stored = NGStore.string(forKey: NetegramAutoFormat.storageKey) {
            // An empty string is a deliberate "off", distinct from never having chosen.
            resolved = NetegramTextStyle(rawValue: stored)
        } else if let legacy = NGStore.stringArray(forKey: NetegramAutoFormat.legacyStorageKey) {
            resolved = NetegramTextStyle.allCases.first(where: { legacy.contains($0.rawValue) })
        } else {
            resolved = nil
        }
        NetegramAutoFormat.cache = .some(resolved)
        return resolved
    }

    public static func setStyle(_ style: NetegramTextStyle?) {
        NGStore.setObject(style?.rawValue ?? "", forKey: NetegramAutoFormat.storageKey)
        NGStore.removeObject(forKey: NetegramAutoFormat.legacyStorageKey)

        NetegramAutoFormat.lock.lock()
        NetegramAutoFormat.cache = nil
        NetegramAutoFormat.lock.unlock()
    }

    /// Captions and the other fields that only rebuild typing attributes.
    public static func applyToTypingAttributes(_ attributes: inout [NSAttributedString.Key: Any]) {
        guard let style = NetegramAutoFormat.style else {
            return
        }
        if attributes[style.inputAttribute] == nil {
            attributes[style.inputAttribute] = true as NSNumber
        }
    }

    /// The chat composer: the whole text in the chosen style, not only what is typed next.
    ///
    /// Typing attributes alone miss everything that is not a keystroke — a paste, an
    /// autocorrect replacement, a restored draft — which is why the style used to show up
    /// only some of the time.
    public static func applyToStateText(_ text: NSMutableAttributedString) {
        guard let style = NetegramAutoFormat.style, text.length > 0 else {
            return
        }
        var excluded: [Range<Int>] = []
        if style == .monospace {
            // Monospace cannot hold a custom emoji or a link: the server strips them from a code
            // span. Those stretches are left out so the emoji and links survive.
            for key in [ChatTextInputAttributes.customEmoji, ChatTextInputAttributes.textMention, ChatTextInputAttributes.textUrl, ChatTextInputAttributes.date] {
                text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length), options: [], using: { value, range, _ in
                    if value != nil {
                        excluded.append(range.location ..< range.location + range.length)
                    }
                })
            }
        }
        for range in netegramRanges(length: text.length, excluding: excluded) {
            text.addAttribute(style.inputAttribute, value: true as NSNumber, range: NSRange(location: range.lowerBound, length: range.count))
        }
    }
}

/// Netegram: puts outgoing text in the auto-format style.
///
/// The composer already shows the style, so for a message typed normally this changes
/// nothing. It is here for everything that reaches sending without passing through that
/// display: pasted text, the native editor, captions, drafts. Any existing entity of the same
/// kind is replaced by one covering the whole text, so the result never carries overlapping
/// duplicates.
///
/// Rich messages — headings, lists, tables — carry their formatting inside the page they
/// describe rather than as entities, and are left exactly as they are.
public func netegramApplyAutoFormat(messages: [EnqueueMessage]) -> [EnqueueMessage] {
    guard let style = NetegramAutoFormat.style else {
        return messages
    }
    return messages.map { message -> EnqueueMessage in
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
            return message
        }
        let length = (text as NSString).length
        guard length > 0 else {
            return message
        }
        if attributes.contains(where: { $0 is RichTextMessageAttribute }) {
            return message
        }

        var existing: [MessageTextEntity] = []
        // The engine alias rather than Postbox's own name: TextFormat does not import Postbox,
        // and TelegramCore does not re-export it.
        var otherAttributes: [EngineMessage.Attribute] = []
        for attribute in attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                existing.append(contentsOf: attribute.entities)
            } else {
                otherAttributes.append(attribute)
            }
        }

        let type = style.entityType
        var entities = existing.filter { $0.type != type }

        var excluded: [Range<Int>] = []
        if style == .monospace {
            for entity in existing {
                switch entity.type {
                case .CustomEmoji, .TextMention, .TextUrl, .Mention, .Url, .Email, .PhoneNumber, .Hashtag, .BotCommand, .BankCard, .FormattedDate, .Pre:
                    excluded.append(entity.range)
                default:
                    break
                }
            }
        }
        for range in netegramRanges(length: length, excluding: excluded) {
            entities.append(MessageTextEntity(range: range, type: type))
        }
        otherAttributes.append(TextEntitiesMessageAttribute(entities: entities))

        return .message(
            text: text,
            attributes: otherAttributes,
            inlineStickers: inlineStickers,
            mediaReference: mediaReference,
            threadId: threadId,
            replyToMessageId: replyToMessageId,
            replyToStoryId: replyToStoryId,
            localGroupingKey: localGroupingKey,
            correlationId: correlationId,
            bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
        )
    }
}

/// `0 ..< length` with the excluded stretches cut out. Empty pieces are dropped.
private func netegramRanges(length: Int, excluding excluded: [Range<Int>]) -> [Range<Int>] {
    guard length > 0 else {
        return []
    }
    let sorted = excluded
        .map { max(0, $0.lowerBound) ..< min(length, $0.upperBound) }
        .filter { !$0.isEmpty }
        .sorted(by: { $0.lowerBound < $1.lowerBound })

    var result: [Range<Int>] = []
    var cursor = 0
    for range in sorted {
        if range.lowerBound > cursor {
            result.append(cursor ..< range.lowerBound)
        }
        cursor = max(cursor, range.upperBound)
    }
    if cursor < length {
        result.append(cursor ..< length)
    }
    return result
}
