import Foundation
import NetegramStore
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

public enum NetegramLookStrings {
    public static let title = "Внешний вид"
    public static let subtitle = "Меню и эффекты"
    public static let contextRedesignTitle = "Редизайн при зажатии сообщения"
    public static let contextRedesignFooter = "Новый невышедший дизайн Telegram: «Выбрать», «Скопировать» и «Удалить» отдельным рядом сверху, остальные действия списком под ним."
    public static let roundButtonsTitle = "Круглые кнопки"
    public static let roundButtonsFooter = "Кнопки действий в профиле становятся круглыми, без подписей, на прозрачном стекле."
    public static let hideButtonsTitle = "Скрытие вкладок в профиле"
    public static let hideButtonsSubtitle = "Звонок, уведомления, поиск, ещё"
    public static let navBarTitle = "Скрытие вкладок навбара"
    public static let navBarSubtitle = "Вкладки и размер нижней панели"
}

/// Read by the chat context menu assembly, which cannot import SettingsUI.
public let netegramContextRedesignKey = "netegram.look.contextRedesign"
/// Read by the profile header, which cannot import SettingsUI either.
public let netegramRoundProfileButtonsKey = "netegram.look.roundProfileButtons"
public let netegramHiddenProfileButtonsKey = "netegram.look.hiddenProfileButtons"
/// Read by TelegramRootController when it assembles the tab bar.
public let netegramHiddenNavTabsKey = "netegram.look.hiddenNavTabs"
/// Read by TabBarUI while laying the bar out. Percentages, 50 to 150.
public let netegramNavBarWidthKey = "netegram.look.navBarWidth"
public let netegramNavBarHeightKey = "netegram.look.navBarHeight"

/// Bottom tab bar entries that can be hidden. Raw values are stored, so they must stay put.
public enum NetegramNavTab: String, CaseIterable {
    case calls
    case contacts
    case chats
    case settings

    public var title: String {
        switch self {
        case .calls:
            return "Скрыть вкладку «Звонки»"
        case .contacts:
            return "Скрыть вкладку «Контакты»"
        case .chats:
            return "Скрыть вкладку «Чаты»"
        case .settings:
            return "Скрыть вкладку «Настройки»"
        }
    }

    public var footer: String {
        switch self {
        case .calls:
            return "Скрывает вкладку «Звонки» в нижней панели."
        case .contacts:
            return "Скрывает вкладку «Контакты» в нижней панели."
        case .chats:
            return "Скрывает вкладку «Чаты» в нижней панели."
        case .settings:
            return "Скрывает вкладку «Настройки» в нижней панели."
        }
    }
}

public func netegramSetNavTabHidden(_ tab: NetegramNavTab, hidden: Bool) {
    var values = NGStore.stringArray(forKey: netegramHiddenNavTabsKey) ?? []
    if hidden {
        if !values.contains(tab.rawValue) {
            values.append(tab.rawValue)
        }
    } else {
        values.removeAll(where: { $0 == tab.rawValue })
    }
    NGStore.setObject(values, forKey: netegramHiddenNavTabsKey)
}

/// Profile action buttons that can be hidden. Raw values are stored, so they must stay put.
public enum NetegramProfileButton: String, CaseIterable {
    case call
    case mute
    case search
    case more

    public var title: String {
        switch self {
        case .call:
            return "Скрыть вкладку «Звонок»"
        case .mute:
            return "Скрыть вкладку «Уведомления»"
        case .search:
            return "Скрыть вкладку «Поиск»"
        case .more:
            return "Скрыть вкладку «Ещё»"
        }
    }

    public var footer: String {
        switch self {
        case .call:
            return "Скрывает вкладку «Звонок» в профиле."
        case .mute:
            return "Скрывает вкладку «Уведомления» в профиле."
        case .search:
            return "Скрывает вкладку «Поиск» в профиле."
        case .more:
            return "Скрывает вкладку «Ещё» в профиле."
        }
    }
}

/// True when the given profile action button should be left out.
///
/// The header lays out only the buttons it is given, so a hidden one simply is not added
/// and the rest close the gap by themselves.
public func netegramIsProfileButtonHidden(_ button: NetegramProfileButton) -> Bool {
    let hidden = NGStore.stringArray(forKey: netegramHiddenProfileButtonsKey) ?? []
    return hidden.contains(button.rawValue)
}

public func netegramSetProfileButtonHidden(_ button: NetegramProfileButton, hidden: Bool) {
    var values = NGStore.stringArray(forKey: netegramHiddenProfileButtonsKey) ?? []
    if hidden {
        if !values.contains(button.rawValue) {
            values.append(button.rawValue)
        }
    } else {
        values.removeAll(where: { $0 == button.rawValue })
    }
    NGStore.setObject(values, forKey: netegramHiddenProfileButtonsKey)
}

public struct NetegramLookSettings: Equatable {
    public let contextRedesign: Bool
    public let roundProfileButtons: Bool
    public let hiddenProfileButtons: [String]
    public let hiddenNavTabs: [String]
    public let navBarWidth: Int
    public let navBarHeight: Int

    public init(contextRedesign: Bool, roundProfileButtons: Bool, hiddenProfileButtons: [String], hiddenNavTabs: [String], navBarWidth: Int, navBarHeight: Int) {
        self.contextRedesign = contextRedesign
        self.roundProfileButtons = roundProfileButtons
        self.hiddenProfileButtons = hiddenProfileButtons
        self.hiddenNavTabs = hiddenNavTabs
        self.navBarWidth = navBarWidth
        self.navBarHeight = navBarHeight
    }
}

public final class NetegramLookPreferences {
    public static let shared = NetegramLookPreferences()

    private let promise: ValuePromise<NetegramLookSettings>

    private init() {
        self.promise = ValuePromise(NetegramLookPreferences.current(), ignoreRepeated: true)
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.promise.set(NetegramLookPreferences.current())
    }

    public static func current() -> NetegramLookSettings {
        return NetegramLookSettings(
            contextRedesign: NGStore.bool(forKey: netegramContextRedesignKey),
            roundProfileButtons: NGStore.bool(forKey: netegramRoundProfileButtonsKey),
            hiddenProfileButtons: NGStore.stringArray(forKey: netegramHiddenProfileButtonsKey) ?? [],
            hiddenNavTabs: NGStore.stringArray(forKey: netegramHiddenNavTabsKey) ?? [],
            navBarWidth: NGStore.object(forKey: netegramNavBarWidthKey) as? Int ?? 100,
            navBarHeight: NGStore.object(forKey: netegramNavBarHeightKey) as? Int ?? 100
        )
    }

    /// Clamped on write as well as on read: the bar has to stay reachable whatever ends up in
    /// the store.
    public func setNavBarWidth(_ percent: Int) {
        NGStore.setObject(max(50, min(150, percent)), forKey: netegramNavBarWidthKey)
        self.promise.set(NetegramLookPreferences.current())
    }

    public func setNavBarHeight(_ percent: Int) {
        NGStore.setObject(max(50, min(150, percent)), forKey: netegramNavBarHeightKey)
        self.promise.set(NetegramLookPreferences.current())
    }

    public func setNavTabHidden(_ tab: NetegramNavTab, hidden: Bool) {
        netegramSetNavTabHidden(tab, hidden: hidden)
        self.promise.set(NetegramLookPreferences.current())
    }

    public func setRoundProfileButtons(_ value: Bool) {
        NGStore.setObject(value, forKey: netegramRoundProfileButtonsKey)
        self.promise.set(NetegramLookPreferences.current())
    }

    public func setProfileButtonHidden(_ button: NetegramProfileButton, hidden: Bool) {
        netegramSetProfileButtonHidden(button, hidden: hidden)
        self.promise.set(NetegramLookPreferences.current())
    }

    public var signal: Signal<NetegramLookSettings, NoError> {
        return self.promise.get()
    }

    public func setContextRedesign(_ value: Bool) {
        NGStore.setObject(value, forKey: netegramContextRedesignKey)
        self.promise.set(NetegramLookPreferences.current())
    }
}

private final class NetegramLookArguments {
    let updateContextRedesign: (Bool) -> Void
    let updateRoundButtons: (Bool) -> Void

    init(updateContextRedesign: @escaping (Bool) -> Void, updateRoundButtons: @escaping (Bool) -> Void) {
        self.updateContextRedesign = updateContextRedesign
        self.updateRoundButtons = updateRoundButtons
    }
}

private enum NetegramLookSection: Int32 {
    case contextRedesign
    case roundButtons
}

private enum NetegramLookEntry: ItemListNodeEntry {
    case contextRedesign(Bool)
    case contextRedesignFooter
    case roundButtons(Bool)
    case roundButtonsFooter

    var section: ItemListSectionId {
        switch self {
        case .contextRedesign, .contextRedesignFooter:
            return NetegramLookSection.contextRedesign.rawValue
        case .roundButtons, .roundButtonsFooter:
            return NetegramLookSection.roundButtons.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .contextRedesign:
            return 0
        case .contextRedesignFooter:
            return 1
        case .roundButtons:
            return 2
        case .roundButtonsFooter:
            return 3
        }
    }

    static func <(lhs: NetegramLookEntry, rhs: NetegramLookEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramLookArguments
        switch self {
        case let .contextRedesign(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramLookStrings.contextRedesignTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateContextRedesign(value)
            })
        case .contextRedesignFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramLookStrings.contextRedesignFooter), sectionId: self.section)
        case let .roundButtons(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramLookStrings.roundButtonsTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRoundButtons(value)
            })
        case .roundButtonsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramLookStrings.roundButtonsFooter), sectionId: self.section)
        }
    }
}

// MARK: - Hiding profile buttons

private final class NetegramHideButtonsArguments {
    let toggle: (NetegramProfileButton, Bool) -> Void

    init(toggle: @escaping (NetegramProfileButton, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum NetegramHideButtonsEntry: ItemListNodeEntry {
    case toggle(index: Int, button: NetegramProfileButton, value: Bool)
    case footer(index: Int, text: String)

    /// A section per pair keeps each toggle in its own block with the caption beneath it.
    var section: ItemListSectionId {
        switch self {
        case let .toggle(index, _, _):
            return ItemListSectionId(index)
        case let .footer(index, _):
            return ItemListSectionId(index)
        }
    }

    var stableId: Int32 {
        switch self {
        case let .toggle(index, _, _):
            return Int32(index * 2)
        case let .footer(index, _):
            return Int32(index * 2 + 1)
        }
    }

    static func <(lhs: NetegramHideButtonsEntry, rhs: NetegramHideButtonsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramHideButtonsArguments
        switch self {
        case let .toggle(_, button, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: button.title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(button, value)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func netegramHideProfileButtonsController(context: AccountContext) -> ViewController {
    let arguments = NetegramHideButtonsArguments(toggle: { button, value in
        NetegramLookPreferences.shared.setProfileButtonHidden(button, hidden: value)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramLookPreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [NetegramHideButtonsEntry] = []
        for (index, button) in NetegramProfileButton.allCases.enumerated() {
            entries.append(.toggle(index: index, button: button, value: settings.hiddenProfileButtons.contains(button.rawValue)))
            entries.append(.footer(index: index, text: button.footer))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramLookStrings.hideButtonsTitle),
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

public func netegramLookController(context: AccountContext) -> ViewController {
    var presentRestartImpl: ((String) -> Void)?

    let arguments = NetegramLookArguments(updateContextRedesign: { value in
        NetegramLookPreferences.shared.setContextRedesign(value)
        presentRestartImpl?(NetegramRestartStrings.contextMenu)
    }, updateRoundButtons: { value in
        NetegramLookPreferences.shared.setRoundProfileButtons(value)
        presentRestartImpl?(NetegramRestartStrings.profileButtons)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramLookPreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [NetegramLookEntry] = [
            .contextRedesign(settings.contextRedesign),
            .contextRedesignFooter,
            .roundButtons(settings.roundProfileButtons),
            .roundButtonsFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramLookStrings.title),
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
    presentRestartImpl = { [weak controller] text in
        netegramPresentRestartToast(context: context, controller: controller, text: text)
    }
    return controller
}
