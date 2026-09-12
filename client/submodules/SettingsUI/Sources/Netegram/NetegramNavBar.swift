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

public enum NetegramNavBarStrings {
    public static let width = "Ширина"
    public static let widthFooter = "Насколько панель уже экрана."
    public static let height = "Высота"
    public static let heightFooter = "Насколько панель толще обычной."
    public static let reset = "Вернуть обычный размер"
}

private final class NetegramNavBarArguments {
    let toggleTab: (NetegramNavTab, Bool) -> Void
    let updateWidth: (Int) -> Void
    let updateHeight: (Int) -> Void
    let reset: () -> Void

    init(toggleTab: @escaping (NetegramNavTab, Bool) -> Void, updateWidth: @escaping (Int) -> Void, updateHeight: @escaping (Int) -> Void, reset: @escaping () -> Void) {
        self.toggleTab = toggleTab
        self.updateWidth = updateWidth
        self.updateHeight = updateHeight
        self.reset = reset
    }
}

private enum NetegramNavBarEntry: ItemListNodeEntry {
    case tab(Int, NetegramNavTab, Bool)
    case tabFooter(Int, String)
    case width(Int)
    case widthFooter
    case height(Int)
    case heightFooter
    case reset

    /// One section per row, so each setting is its own block with its caption underneath.
    var section: ItemListSectionId {
        switch self {
        case let .tab(index, _, _), let .tabFooter(index, _):
            return ItemListSectionId(index)
        case .width, .widthFooter:
            return ItemListSectionId(100)
        case .height, .heightFooter:
            return ItemListSectionId(101)
        case .reset:
            return ItemListSectionId(102)
        }
    }

    var stableId: Int32 {
        switch self {
        case let .tab(index, _, _):
            return Int32(index * 2)
        case let .tabFooter(index, _):
            return Int32(index * 2 + 1)
        case .width: return 100
        case .widthFooter: return 101
        case .height: return 102
        case .heightFooter: return 103
        case .reset: return 104
        }
    }

    static func <(lhs: NetegramNavBarEntry, rhs: NetegramNavBarEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramNavBarArguments
        switch self {
        case let .tab(_, tab, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: tab.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleTab(tab, value)
            })
        case let .tabFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .width(percent):
            // The slider counts from zero, so the stored percentage is shifted into its range
            // and back rather than the slider being taught about percentages.
            return NetegramStarsSliderItem(theme: presentationData.theme, title: "\(NetegramNavBarStrings.width): \(percent)%", value: percent - 50, maxValue: 100, enabled: true, sectionId: self.section, updated: { value in
                arguments.updateWidth(value + 50)
            })
        case .widthFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramNavBarStrings.widthFooter), sectionId: self.section)
        case let .height(percent):
            return NetegramStarsSliderItem(theme: presentationData.theme, title: "\(NetegramNavBarStrings.height): \(percent)%", value: percent - 50, maxValue: 100, enabled: true, sectionId: self.section, updated: { value in
                arguments.updateHeight(value + 50)
            })
        case .heightFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramNavBarStrings.heightFooter), sectionId: self.section)
        case .reset:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: NetegramNavBarStrings.reset, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        }
    }
}

/// Left to right, as the real bar arranges them.
extension NetegramNavTab {
    static var barOrder: [NetegramNavTab] {
        return [.contacts, .calls, .chats, .settings]
    }
}

public func netegramNavBarController(context: AccountContext) -> ViewController {
    var presentRestartImpl: (() -> Void)?

    let arguments = NetegramNavBarArguments(toggleTab: { tab, value in
        NetegramLookPreferences.shared.setNavTabHidden(tab, hidden: value)
        presentRestartImpl?()
    }, updateWidth: { percent in
        NetegramLookPreferences.shared.setNavBarWidth(percent)
    }, updateHeight: { percent in
        NetegramLookPreferences.shared.setNavBarHeight(percent)
    }, reset: {
        NetegramLookPreferences.shared.setNavBarWidth(100)
        NetegramLookPreferences.shared.setNavBarHeight(100)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramLookPreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [NetegramNavBarEntry] = []
        for (index, tab) in NetegramNavTab.barOrder.enumerated() {
            entries.append(.tab(index, tab, settings.hiddenNavTabs.contains(tab.rawValue)))
            entries.append(.tabFooter(index, tab.footer))
        }
        entries.append(.width(settings.navBarWidth))
        entries.append(.widthFooter)
        entries.append(.height(settings.navBarHeight))
        entries.append(.heightFooter)
        entries.append(.reset)

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramLookStrings.navBarTitle),
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
        netegramPresentRestartToast(context: context, controller: controller, text: NetegramRestartStrings.navBar)
    }
    return controller
}
