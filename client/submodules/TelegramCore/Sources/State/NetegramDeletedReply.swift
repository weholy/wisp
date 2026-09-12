import Foundation
import Postbox
import SwiftSignalKit

/// Netegram: replying to a message the sender took back.
///
/// Anti-revoke keeps such a message in this client's database, so you can still see it and
/// still reply to it. The other side cannot: the message is gone from the server, so a reply
/// pointing at it arrives with nothing attached — the recipient sees a bare answer to a
/// question they can no longer read, and often no reply header at all.
///
/// So the quote is carried in the message body instead. The text that was deleted goes in a
/// blockquote, the answer goes underneath, and the reply link — which the server would reject
/// or silently drop — is removed:
///
///     ┌ the text of the deleted message
///     └
///     the answer
///
/// Only outgoing text is touched, and only when the reply target is one of the kept messages.
/// Everything else goes out exactly as before.
public func netegramTransformDeletedReplies(postbox: Postbox, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
    // The overwhelmingly common case is that nothing here replies to a deleted message. Deciding
    // that costs a set lookup per message, and skipping the transaction keeps sending on the
    // fast path it has always been on.
    var affected = false
    for message in messages {
        if case let .message(_, _, _, _, _, replyToMessageId, _, _, _, _) = message, let replyToMessageId {
            if NetegramDeletedMessages.contains(replyToMessageId.messageId) {
                affected = true
                break
            }
        }
    }
    guard affected else {
        return .single(messages)
    }

    return postbox.transaction { transaction -> [EnqueueMessage] in
        return messages.map { message -> EnqueueMessage in
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
                return message
            }
            guard let replyToMessageId, NetegramDeletedMessages.contains(replyToMessageId.messageId) else {
                return message
            }
            guard let original = transaction.getMessage(replyToMessageId.messageId) else {
                // Tracked as deleted but no longer in the database — nothing to quote, and the
                // reply link is still dead, so drop it rather than send a broken one.
                return message.withUpdatedReplyToMessageId(nil)
            }

            // A quote the user selected by hand wins over the whole message: it is the part
            // they meant to answer.
            let quotedText = replyToMessageId.quote?.text ?? original.text
            let trimmedQuote = quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuote.isEmpty else {
                // A deleted photo or sticker has no text to carry over. The reply link is dead
                // either way, so it goes; the answer is sent on its own.
                return message.withUpdatedReplyToMessageId(nil)
            }

            let separator = "\n"
            let combinedText = trimmedQuote + separator + text

            // Ranges are in UTF-16 units, which is what MessageTextEntity counts in and what
            // the server expects — not Characters, and not bytes.
            let quoteLength = (trimmedQuote as NSString).length
            let offset = quoteLength + (separator as NSString).length

            var entities: [MessageTextEntity] = [
                MessageTextEntity(range: 0 ..< quoteLength, type: .BlockQuote(isCollapsed: false))
            ]

            var updatedAttributes: [MessageAttribute] = []
            for attribute in attributes {
                if let attribute = attribute as? TextEntitiesMessageAttribute {
                    // Everything the user formatted in their own answer keeps its formatting;
                    // the ranges simply move down by the length of the quote in front of it.
                    for entity in attribute.entities {
                        entities.append(MessageTextEntity(range: (entity.range.lowerBound + offset) ..< (entity.range.upperBound + offset), type: entity.type))
                    }
                } else {
                    updatedAttributes.append(attribute)
                }
            }
            updatedAttributes.append(TextEntitiesMessageAttribute(entities: entities))

            return .message(
                text: combinedText,
                attributes: updatedAttributes,
                inlineStickers: inlineStickers,
                mediaReference: mediaReference,
                threadId: threadId,
                replyToMessageId: nil,
                replyToStoryId: replyToStoryId,
                localGroupingKey: localGroupingKey,
                correlationId: correlationId,
                bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
            )
        }
    }
}
