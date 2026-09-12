import Foundation
import TelegramCore

/// Matches the Bot API's own custom-emoji syntax, e.g.
/// `<tg-emoji emoji-id="5368324170671202286">⭐</tg-emoji>`.
///
/// Bots may only send real `custom_emoji` entities once they own a Fragment username;
/// without one Telegram strips the entity server-side and the client receives plain text.
/// So we look for the literal markup that survives as text and rebuild the entity locally.
private let netegramPremiumEmojiRegex = try? NSRegularExpression(
    pattern: "<tg-emoji\\s+emoji-id=\"(\\d+)\"\\s*>(.*?)</tg-emoji>",
    options: [.caseInsensitive, .dotMatchesLineSeparators]
)

/// Rewrites `<tg-emoji>` markup into a real custom-emoji entity.
///
/// Returns nil when the text contains no markup, so callers can skip the work entirely.
/// This is display-only: the rewritten message is never sent anywhere, so only this device
/// shows the emoji — everyone else keeps seeing the raw markup.
///
/// Offsets in `MessageTextEntity` are UTF-16 code unit indices, and removing the tags
/// shifts everything after them, so pre-existing entities are remapped rather than copied.
public func netegramSubstitutePremiumEmoji(text: String, entities: [MessageTextEntity]) -> (text: String, entities: [MessageTextEntity])? {
    guard let regex = netegramPremiumEmojiRegex else {
        return nil
    }
    let source = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
    guard !matches.isEmpty else {
        return nil
    }

    var result = ""
    var addedEntities: [MessageTextEntity] = []

    // Maps a UTF-16 offset in the source onto its offset in the result. Offsets inside a
    // removed tag collapse onto the position the tag occupied.
    var offsetMap = [Int](repeating: 0, count: source.length + 1)

    // Sequential walk: copy the span before each match, then the match's inner text.
    var sourceIndex = 0
    var resultLength = 0
    for match in matches {
        let matchRange = match.range
        let idRange = match.range(at: 1)
        let innerRange = match.range(at: 2)

        // text before the tag is copied verbatim
        if matchRange.location > sourceIndex {
            let plainRange = NSRange(location: sourceIndex, length: matchRange.location - sourceIndex)
            for offset in plainRange.location ..< (plainRange.location + plainRange.length) {
                offsetMap[offset] = resultLength + (offset - plainRange.location)
            }
            result += source.substring(with: plainRange)
            resultLength += plainRange.length
        }

        // the opening tag collapses onto the start of the inner text
        for offset in matchRange.location ..< innerRange.location {
            offsetMap[offset] = resultLength
        }

        let inner = source.substring(with: innerRange)
        for offset in innerRange.location ..< (innerRange.location + innerRange.length) {
            offsetMap[offset] = resultLength + (offset - innerRange.location)
        }
        let innerStart = resultLength
        result += inner
        resultLength += innerRange.length

        // the closing tag collapses onto the end of the inner text
        for offset in (innerRange.location + innerRange.length) ..< (matchRange.location + matchRange.length) {
            offsetMap[offset] = resultLength
        }

        if innerRange.length > 0, let fileId = Int64(source.substring(with: idRange)) {
            addedEntities.append(MessageTextEntity(
                range: innerStart ..< (innerStart + innerRange.length),
                type: .CustomEmoji(stickerPack: nil, fileId: fileId)
            ))
        }

        sourceIndex = matchRange.location + matchRange.length
    }

    // trailing text after the last tag
    if sourceIndex < source.length {
        let tailRange = NSRange(location: sourceIndex, length: source.length - sourceIndex)
        for offset in tailRange.location ..< (tailRange.location + tailRange.length) {
            offsetMap[offset] = resultLength + (offset - tailRange.location)
        }
        result += source.substring(with: tailRange)
        resultLength += tailRange.length
    }
    offsetMap[source.length] = resultLength

    // carry the original entities across, dropping any that collapsed to nothing
    var remappedEntities: [MessageTextEntity] = []
    for entity in entities {
        let lower = min(max(entity.range.lowerBound, 0), source.length)
        let upper = min(max(entity.range.upperBound, 0), source.length)
        guard lower < upper else {
            continue
        }
        let newLower = offsetMap[lower]
        let newUpper = offsetMap[upper]
        if newLower < newUpper {
            remappedEntities.append(MessageTextEntity(range: newLower ..< newUpper, type: entity.type))
        }
    }

    remappedEntities.append(contentsOf: addedEntities)
    remappedEntities.sort(by: { $0.range.lowerBound < $1.range.lowerBound })

    return (result, remappedEntities)
}
