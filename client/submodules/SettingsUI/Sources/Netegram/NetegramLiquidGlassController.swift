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

private final class NetegramLiquidGlassControllerArguments {
    let updateMessages: (Bool) -> Void
    let updateInlineButtons: (Bool) -> Void
    let updateInputPanel: (Bool) -> Void
    let updateTabBar: (Bool) -> Void

    init(updateMessages: @escaping (Bool) -> Void, updateInlineButtons: @escaping (Bool) -> Void, updateInputPanel: @escaping (Bool) -> Void, updateTabBar: @escaping (Bool) -> Void) {
        self.updateMessages = updateMessages
        self.updateInlineButtons = updateInlineButtons
        self.updateInputPanel = updateInputPanel
        self.updateTabBar = updateTabBar
    }
}

/// One toggle per row, so each stands in its own block with its caption underneath — the
/// same layout every other Netegram screen uses.
///
/// Four surfaces and no blanket switch. "Liquid Glass everywhere" and the chat-list header
/// toggle used to sit at the bottom of this screen; both are gone.
private enum NetegramLiquidGlassEntry: ItemListNodeEntry {
    case messages(Bool)
    case messagesFooter
    case inlineButtons(Bool)
    case inlineButtonsFooter
    case inputPanel(Bool)
    case inputPanelFooter
    case tabBar(Bool)
    case tabBarFooter

    var section: ItemListSectionId {
        switch self {
        case .messages, .messagesFooter: return 0
        case .inlineButtons, .inlineButtonsFooter: return 1
        case .inputPanel, .inputPanelFooter: return 2
        case .tabBar, .tabBarFooter: return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .messages: return 0
        case .messagesFooter: return 1
        case .inlineButtons: return 2
        case .inlineButtonsFooter: return 3
        case .inputPanel: return 4
        case .inputPanelFooter: return 5
        case .tabBar: return 6
        case .tabBarFooter: return 7
        }
    }

    static func <(lhs: NetegramLiquidGlassEntry, rhs: NetegramLiquidGlassEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramLiquidGlassControllerArguments
        switch self {
        case let .messages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramStrings.liquidGlassMessagesTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateMessages(value)
            })
        case .messagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramStrings.liquidGlassMessagesFooter), sectionId: self.section)
        case let .inlineButtons(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramStrings.liquidGlassInlineButtonsTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateInlineButtons(value)
            })
        case .inlineButtonsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramStrings.liquidGlassInlineButtonsFooter), sectionId: self.section)
        case let .inputPanel(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramStrings.liquidGlassInputPanelTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateInputPanel(value)
            })
        case .inputPanelFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramStrings.liquidGlassInputPanelFooter), sectionId: self.section)
        case let .tabBar(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramStrings.liquidGlassTabBarTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateTabBar(value)
            })
        case .tabBarFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramStrings.liquidGlassTabBarFooter), sectionId: self.section)
        }
    }
}

public func netegramLiquidGlassController(context: AccountContext) -> ViewController {
    var presentRestartImpl: (() -> Void)?

    let arguments = NetegramLiquidGlassControllerArguments(updateMessages: { value in
        NetegramSettings.shared.setLiquidGlassMessages(value)
        presentRestartImpl?()
    }, updateInlineButtons: { value in
        NetegramSettings.shared.setLiquidGlassInlineButtons(value)
        presentRestartImpl?()
    }, updateInputPanel: { value in
        NetegramSettings.shared.setLiquidGlassInputPanel(value)
        presentRestartImpl?()
    }, updateTabBar: { value in
        NetegramSettings.shared.setLiquidGlassTabBar(value)
        presentRestartImpl?()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramSettings.shared.liquidGlassSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, glass -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [NetegramLiquidGlassEntry] = [
            .messages(glass.messages),
            .messagesFooter,
            .inlineButtons(glass.inlineButtons),
            .inlineButtonsFooter,
            .inputPanel(glass.inputPanel),
            .inputPanelFooter,
            .tabBar(glass.tabBar),
            .tabBarFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramStrings.liquidGlass),
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
    presentRestartImpl = { [weak controller] in
        netegramPresentRestartToast(context: context, controller: controller, text: NetegramRestartStrings.glass)
    }
    return controller
}
