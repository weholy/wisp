import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI

public enum NetegramPeerToolsStrings {
    public static let title = "Netegram"
    public static let ratingHeader = "РЕЙТИНГ"
    public static let ratingStars = "Количество звёзд"
    public static let ratingLevel = "Уровень"
    public static let ratingAuto = "по звёздам"
    public static let ratingFooter = "Рейтинг видите только вы."
    public static let usernameHeader = "ЮЗЕРНЕЙМ"
    public static let username = "Локальный юзернейм"
    public static let usernameReset = "Сбросить юзернейм"
    public static let usernameFooter = "Юзернейм меняется только у вас."
}

/// What the profile submenu can edit for a peer.
public enum NetegramPeerToolKind {
    case ratingStars
    case ratingLevel
    case username

    public var title: String {
        switch self {
        case .ratingStars:
            return NetegramPeerToolsStrings.ratingStars
        case .ratingLevel:
            return NetegramPeerToolsStrings.ratingLevel
        case .username:
            return NetegramPeerToolsStrings.username
        }
    }
}

/// Shows the input prompt for one of the per-peer overrides.
///
/// Lives here so the profile screen does not need to depend on PromptUI: it only knows
/// which value the user picked from the submenu.
public func netegramPresentPeerToolPrompt(context: AccountContext, peerId: EnginePeer.Id, kind: NetegramPeerToolKind, parentController: ViewController) {
    let current: String
    switch kind {
    case .ratingStars:
        let value = netegramCurrentLocalRatingStars(for: peerId)
        current = value > 0 ? "\(value)" : ""
    case .ratingLevel:
        current = netegramCurrentLocalRatingLevel(for: peerId).map { "\($0)" } ?? ""
    case .username:
        current = netegramCurrentLocalUsername(for: peerId) ?? ""
    }

    let inputController = promptController(
        context: context,
        text: kind.title,
        value: current,
        apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            switch kind {
            case .ratingStars:
                netegramSetLocalRatingStars(Int(trimmed) ?? 0, for: peerId)
            case .ratingLevel:
                // An empty field hands the level back to the star count.
                netegramSetLocalRatingLevel(trimmed.isEmpty ? nil : Int(trimmed), for: peerId)
            case .username:
                netegramSetLocalUsername(trimmed, for: peerId)
            }
        }
    )
    parentController.present(inputController, in: .window(.root))
}

/// Clears a peer's local username override.
public func netegramResetLocalUsername(for peerId: EnginePeer.Id) {
    netegramSetLocalUsername(nil, for: peerId)
}

private final class NetegramPeerToolsArguments {
    let editStars: (Int) -> Void
    let editLevel: (Int?) -> Void
    let editUsername: (String) -> Void
    let resetUsername: () -> Void

    init(editStars: @escaping (Int) -> Void, editLevel: @escaping (Int?) -> Void, editUsername: @escaping (String) -> Void, resetUsername: @escaping () -> Void) {
        self.editStars = editStars
        self.editLevel = editLevel
        self.editUsername = editUsername
        self.resetUsername = resetUsername
    }
}

private enum NetegramPeerToolsSection: Int32 {
    case rating
    case username
}

private enum NetegramPeerToolsEntry: ItemListNodeEntry {
    case ratingHeader
    case ratingStars(Int)
    case ratingLevel(String)
    case ratingFooter
    case usernameHeader
    case username(String)
    case usernameReset(Bool)
    case usernameFooter

    var section: ItemListSectionId {
        switch self {
        case .ratingHeader, .ratingStars, .ratingLevel, .ratingFooter:
            return NetegramPeerToolsSection.rating.rawValue
        case .usernameHeader, .username, .usernameReset, .usernameFooter:
            return NetegramPeerToolsSection.username.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ratingHeader:
            return 0
        case .ratingStars:
            return 1
        case .ratingLevel:
            return 2
        case .ratingFooter:
            return 3
        case .usernameHeader:
            return 4
        case .username:
            return 5
        case .usernameReset:
            return 6
        case .usernameFooter:
            return 7
        }
    }

    static func <(lhs: NetegramPeerToolsEntry, rhs: NetegramPeerToolsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramPeerToolsArguments
        switch self {
        case .ratingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramPeerToolsStrings.ratingHeader, sectionId: self.section)
        case let .ratingStars(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramPeerToolsStrings.ratingStars, label: "\(value)", sectionId: self.section, style: .blocks, action: {
                arguments.editStars(value)
            })
        case let .ratingLevel(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramPeerToolsStrings.ratingLevel, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editLevel(nil)
            })
        case .ratingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramPeerToolsStrings.ratingFooter), sectionId: self.section)
        case .usernameHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramPeerToolsStrings.usernameHeader, sectionId: self.section)
        case let .username(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramPeerToolsStrings.username, label: value.isEmpty ? "" : "@\(value)", sectionId: self.section, style: .blocks, action: {
                arguments.editUsername(value)
            })
        case let .usernameReset(enabled):
            return ItemListActionItem(presentationData: presentationData, title: NetegramPeerToolsStrings.usernameReset, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetUsername()
            })
        case .usernameFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramPeerToolsStrings.usernameFooter), sectionId: self.section)
        }
    }
}

/// Per-peer Netegram tools, opened from the profile's three-dot menu.
///
/// The overrides themselves already work — the rating is substituted where cached peer data
/// arrives from the server, the username where the client reads `addressName`. This screen
/// only gives them a place to be set from.
public func netegramPeerToolsController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    var presentInputImpl: ((String, String, @escaping (String) -> Void) -> Void)?
    let statePromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0

    let bumpState: () -> Void = {
        revision += 1
        statePromise.set(revision)
    }

    let arguments = NetegramPeerToolsArguments(editStars: { current in
        presentInputImpl?(NetegramPeerToolsStrings.ratingStars, "\(current)", { value in
            netegramSetLocalRatingStars(Int(value) ?? 0, for: peerId)
            bumpState()
        })
    }, editLevel: { _ in
        let current = netegramCurrentLocalRatingLevel(for: peerId)
        presentInputImpl?(NetegramPeerToolsStrings.ratingLevel, current.map { "\($0)" } ?? "", { value in
            // An empty field hands the level back to the star count.
            netegramSetLocalRatingLevel(value.isEmpty ? nil : Int(value), for: peerId)
            bumpState()
        })
    }, editUsername: { current in
        presentInputImpl?(NetegramPeerToolsStrings.username, current, { value in
            netegramSetLocalUsername(value, for: peerId)
            bumpState()
        })
    }, resetUsername: {
        netegramSetLocalUsername(nil, for: peerId)
        bumpState()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let stars = netegramCurrentLocalRatingStars(for: peerId)
        let explicitLevel = netegramCurrentLocalRatingLevel(for: peerId)
        let username = netegramCurrentLocalUsername(for: peerId) ?? ""

        let levelLabel: String
        if let explicitLevel {
            levelLabel = "\(explicitLevel)"
        } else {
            levelLabel = NetegramPeerToolsStrings.ratingAuto
        }

        let entries: [NetegramPeerToolsEntry] = [
            .ratingHeader,
            .ratingStars(stars),
            .ratingLevel(levelLabel),
            .ratingFooter,
            .usernameHeader,
            .username(username),
            .usernameReset(!username.isEmpty),
            .usernameFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramPeerToolsStrings.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentInputImpl = { [weak controller] title, current, apply in
        guard let controller else {
            return
        }
        let inputController = promptController(
            context: context,
            text: title,
            value: current,
            apply: { value in
                if let value {
                    apply(value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                }
            }
        )
        controller.present(inputController, in: .window(.root))
    }
    return controller
}
