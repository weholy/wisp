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
import PromptUI

public enum NetegramAnnouncementStrings {
    public static let title = "Объявление"
    public static let enabled = "Показывать плашку"
    public static let enabledFooter = "Плашка появляется над списком чатов при каждом запуске, пока пользователь её не закроет."
    public static let sourceHeader = "ИСТОЧНИК"
    public static let channel = "Канал"
    public static let channelPlaceholder = "@weholy"
    public static let channelFooter = "Клиент читает закреплённое сообщение этого канала. Первая строка становится заголовком, остальное — описанием, ссылка берётся из сообщения."
    public static let contentHeader = "СОДЕРЖИМОЕ"
    public static let bannerTitle = "Заголовок"
    public static let bannerText = "Описание"
    public static let bannerLink = "Ссылка"
    public static let contentFooter = "Значения ниже используются, пока канал недоступен, и как предпросмотр."
}

/// Only this account sees the editor. Not a security boundary — anyone with the sources can
/// change the number — just a switch that keeps the panel out of other people's builds.
public let netegramAnnouncementOwnerId: Int64 = 8323057352

private let announcementEnabledKey = "netegram.announcement.enabled"
private let announcementChannelKey = "netegram.announcement.channel"
private let announcementTitleKey = "netegram.announcement.title"
private let announcementTextKey = "netegram.announcement.text"
private let announcementLinkKey = "netegram.announcement.link"

public struct NetegramAnnouncement: Equatable {
    public let enabled: Bool
    public let channel: String
    public let title: String
    public let text: String
    public let link: String

    public init(enabled: Bool, channel: String, title: String, text: String, link: String) {
        self.enabled = enabled
        self.channel = channel
        self.title = title
        self.text = text
        self.link = link
    }

    public var isPresentable: Bool {
        return self.enabled && !self.title.isEmpty
    }
}

public final class NetegramAnnouncementSettings {
    public static let shared = NetegramAnnouncementSettings()

    private let promise: ValuePromise<NetegramAnnouncement>

    private init() {
        self.promise = ValuePromise(NetegramAnnouncementSettings.current(), ignoreRepeated: true)
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.promise.set(NetegramAnnouncementSettings.current())
    }

    public static func current() -> NetegramAnnouncement {
        return NetegramAnnouncement(
            enabled: NGStore.bool(forKey: announcementEnabledKey),
            channel: NGStore.string(forKey: announcementChannelKey) ?? "",
            title: NGStore.string(forKey: announcementTitleKey) ?? "",
            text: NGStore.string(forKey: announcementTextKey) ?? "",
            link: NGStore.string(forKey: announcementLinkKey) ?? ""
        )
    }

    public var signal: Signal<NetegramAnnouncement, NoError> {
        return self.promise.get()
    }

    public func setEnabled(_ value: Bool) {
        NGStore.setObject(value, forKey: announcementEnabledKey)
        self.push()
    }

    public func setChannel(_ value: String) {
        NGStore.setObject(value, forKey: announcementChannelKey)
        self.push()
    }

    public func setTitle(_ value: String) {
        NGStore.setObject(value, forKey: announcementTitleKey)
        self.push()
    }

    public func setText(_ value: String) {
        NGStore.setObject(value, forKey: announcementTextKey)
        self.push()
    }

    public func setLink(_ value: String) {
        NGStore.setObject(value, forKey: announcementLinkKey)
        self.push()
    }

    private func push() {
        self.promise.set(NetegramAnnouncementSettings.current())
    }
}

// MARK: - Editor

private final class NetegramAnnouncementArguments {
    let updateEnabled: (Bool) -> Void
    let editChannel: (String) -> Void
    let editTitle: (String) -> Void
    let editText: (String) -> Void
    let editLink: (String) -> Void

    init(
        updateEnabled: @escaping (Bool) -> Void,
        editChannel: @escaping (String) -> Void,
        editTitle: @escaping (String) -> Void,
        editText: @escaping (String) -> Void,
        editLink: @escaping (String) -> Void
    ) {
        self.updateEnabled = updateEnabled
        self.editChannel = editChannel
        self.editTitle = editTitle
        self.editText = editText
        self.editLink = editLink
    }
}

private enum NetegramAnnouncementSection: Int32 {
    case toggle
    case source
    case content
}

private enum NetegramAnnouncementEntry: ItemListNodeEntry {
    case enabled(Bool)
    case enabledFooter
    case sourceHeader
    case channel(String)
    case channelFooter
    case contentHeader
    case bannerTitle(String)
    case bannerText(String)
    case bannerLink(String)
    case contentFooter

    var section: ItemListSectionId {
        switch self {
        case .enabled, .enabledFooter:
            return NetegramAnnouncementSection.toggle.rawValue
        case .sourceHeader, .channel, .channelFooter:
            return NetegramAnnouncementSection.source.rawValue
        case .contentHeader, .bannerTitle, .bannerText, .bannerLink, .contentFooter:
            return NetegramAnnouncementSection.content.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .enabled:
            return 0
        case .enabledFooter:
            return 1
        case .sourceHeader:
            return 2
        case .channel:
            return 3
        case .channelFooter:
            return 4
        case .contentHeader:
            return 5
        case .bannerTitle:
            return 6
        case .bannerText:
            return 7
        case .bannerLink:
            return 8
        case .contentFooter:
            return 9
        }
    }

    static func <(lhs: NetegramAnnouncementEntry, rhs: NetegramAnnouncementEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramAnnouncementArguments
        switch self {
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAnnouncementStrings.enabled, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateEnabled(value)
            })
        case .enabledFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramAnnouncementStrings.enabledFooter), sectionId: self.section)
        case .sourceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramAnnouncementStrings.sourceHeader, sectionId: self.section)
        case let .channel(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAnnouncementStrings.channel, label: value.isEmpty ? NetegramAnnouncementStrings.channelPlaceholder : value, sectionId: self.section, style: .blocks, action: {
                arguments.editChannel(value)
            })
        case .channelFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramAnnouncementStrings.channelFooter), sectionId: self.section)
        case .contentHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramAnnouncementStrings.contentHeader, sectionId: self.section)
        case let .bannerTitle(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAnnouncementStrings.bannerTitle, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.editTitle(value)
            })
        case let .bannerText(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAnnouncementStrings.bannerText, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.editText(value)
            })
        case let .bannerLink(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAnnouncementStrings.bannerLink, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.editLink(value)
            })
        case .contentFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramAnnouncementStrings.contentFooter), sectionId: self.section)
        }
    }
}

public func netegramAnnouncementController(context: AccountContext) -> ViewController {
    var presentEditImpl: ((String, String, @escaping (String) -> Void) -> Void)?

    let arguments = NetegramAnnouncementArguments(updateEnabled: { value in
        NetegramAnnouncementSettings.shared.setEnabled(value)
    }, editChannel: { current in
        presentEditImpl?(NetegramAnnouncementStrings.channel, current, { value in
            NetegramAnnouncementSettings.shared.setChannel(value)
        })
    }, editTitle: { current in
        presentEditImpl?(NetegramAnnouncementStrings.bannerTitle, current, { value in
            NetegramAnnouncementSettings.shared.setTitle(value)
        })
    }, editText: { current in
        presentEditImpl?(NetegramAnnouncementStrings.bannerText, current, { value in
            NetegramAnnouncementSettings.shared.setText(value)
        })
    }, editLink: { current in
        presentEditImpl?(NetegramAnnouncementStrings.bannerLink, current, { value in
            NetegramAnnouncementSettings.shared.setLink(value)
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramAnnouncementSettings.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, announcement -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [NetegramAnnouncementEntry] = [
            .enabled(announcement.enabled),
            .enabledFooter,
            .sourceHeader,
            .channel(announcement.channel),
            .channelFooter,
            .contentHeader,
            .bannerTitle(announcement.title),
            .bannerText(announcement.text),
            .bannerLink(announcement.link),
            .contentFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramAnnouncementStrings.title),
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
    presentEditImpl = { [weak controller] title, current, apply in
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
