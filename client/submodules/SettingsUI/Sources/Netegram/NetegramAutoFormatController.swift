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
import TextFormat

public enum NetegramAutoFormatStrings {
    public static let title = "Автоформат"
    public static let subtitle = "Стиль текста по умолчанию"
    public static let header = "СТИЛЬ"
    public static let footer = "Всё, что вы пишете, уйдёт этим стилем. Выбрать можно только один."
}

private final class NetegramAutoFormatArguments {
    let updateStyle: (NetegramTextStyle, Bool) -> Void

    init(updateStyle: @escaping (NetegramTextStyle, Bool) -> Void) {
        self.updateStyle = updateStyle
    }
}

/// One block for the whole list: these are alternatives within one decision.
private enum NetegramAutoFormatEntry: ItemListNodeEntry {
    case header
    case style(index: Int, style: NetegramTextStyle, value: Bool)
    case footer

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .style(index, _, _):
            return Int32(1 + index)
        case .footer:
            return Int32(1 + NetegramTextStyle.allCases.count)
        }
    }

    static func <(lhs: NetegramAutoFormatEntry, rhs: NetegramAutoFormatEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramAutoFormatArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramAutoFormatStrings.header, sectionId: self.section)
        case let .style(_, style, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: style.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateStyle(style, value)
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramAutoFormatStrings.footer), sectionId: self.section)
        }
    }
}

public func netegramAutoFormatController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise<NetegramTextStyle?>(NetegramAutoFormat.style, ignoreRepeated: true)

    // Switches that behave like a choice: turning one on picks it and turns the rest off,
    // turning the chosen one off leaves nothing chosen.
    let arguments = NetegramAutoFormatArguments(updateStyle: { style, value in
        if value {
            NetegramAutoFormat.setStyle(style)
        } else if NetegramAutoFormat.style == style {
            NetegramAutoFormat.setStyle(nil)
        }
        statePromise.set(NetegramAutoFormat.style)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, selected -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [NetegramAutoFormatEntry] = [.header]
        for (index, style) in NetegramTextStyle.allCases.enumerated() {
            entries.append(.style(index: index, style: style, value: selected == style))
        }
        entries.append(.footer)

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramAutoFormatStrings.title),
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

    return ItemListController(context: context, state: signal)
}
