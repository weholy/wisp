import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class NetegramFakeArguments {
    let updateActivityEnabled: (Bool) -> Void
    let openKind: () -> Void
    let openActivityPeers: () -> Void
    let updateReadEnabled: (Bool) -> Void
    let openReadPeers: () -> Void

    init(updateActivityEnabled: @escaping (Bool) -> Void, openKind: @escaping () -> Void, openActivityPeers: @escaping () -> Void, updateReadEnabled: @escaping (Bool) -> Void, openReadPeers: @escaping () -> Void) {
        self.updateActivityEnabled = updateActivityEnabled
        self.openKind = openKind
        self.openActivityPeers = openActivityPeers
        self.updateReadEnabled = updateReadEnabled
        self.openReadPeers = openReadPeers
    }
}

private enum NetegramFakeSection: Int32 {
    case activity
    case read
}

private enum NetegramFakeEntry: ItemListNodeEntry {
    case activityHeader
    case activityEnabled(Bool)
    case activityKind(String, Bool)
    case activityPeers(Int, Bool)
    case activityFooter
    case readHeader
    case readEnabled(Bool)
    case readPeers(Int, Bool)
    case readFooter

    var section: ItemListSectionId {
        switch self {
        case .activityHeader, .activityEnabled, .activityKind, .activityPeers, .activityFooter:
            return NetegramFakeSection.activity.rawValue
        case .readHeader, .readEnabled, .readPeers, .readFooter:
            return NetegramFakeSection.read.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .activityHeader: return 0
        case .activityEnabled: return 1
        case .activityKind: return 2
        case .activityPeers: return 3
        case .activityFooter: return 4
        case .readHeader: return 5
        case .readEnabled: return 6
        case .readPeers: return 7
        case .readFooter: return 8
        }
    }

    static func <(lhs: NetegramFakeEntry, rhs: NetegramFakeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramFakeArguments
        switch self {
        case .activityHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramFakeStrings.activityHeader, sectionId: self.section)
        case let .activityEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.activityEnabled, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateActivityEnabled(value)
            })
        case let .activityKind(title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.activityKind, enabled: enabled, label: title, sectionId: self.section, style: .blocks, action: {
                arguments.openKind()
            })
        case let .activityPeers(count, enabled):
            let label = count == 0 ? NetegramFakeStrings.activityPeersEmpty : "\(count)"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.activityPeers, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openActivityPeers()
            })
        case .activityFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramFakeStrings.activityFooter), sectionId: self.section)
        case .readHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: NetegramFakeStrings.readHeader, sectionId: self.section)
        case let .readEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.readEnabled, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateReadEnabled(value)
            })
        case let .readPeers(count, enabled):
            let label = count == 0 ? NetegramFakeStrings.activityPeersEmpty : "\(count)"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.readPeers, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openReadPeers()
            })
        case .readFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramFakeStrings.readFooter), sectionId: self.section)
        }
    }
}

/// Opens Telegram's own chat picker and hands back what was chosen.
///
/// Channels and bots are excluded: a channel has no one to show an action to, and a bot does
/// not look. Contacts stay in, since those are the chats this is for.
private func netegramPresentPeerPicker(context: AccountContext, selected: [Int64], parentController: ViewController, completion: @escaping ([Int64]) -> Void) {
    let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
        context: context,
        mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: NetegramFakeStrings.chooseTitle,
            searchPlaceholder: NetegramFakeStrings.choosePlaceholder,
            selectedChats: Set(selected.map { PeerId($0) }),
            additionalCategories: ContactMultiselectionControllerAdditionalCategories(categories: [], selectedCategories: Set()),
            chatListFilters: nil,
            onlyUsers: false,
            disableChannels: true,
            disableBots: true,
            disableContacts: false
        ))
    ))

    let _ = (controller.result
    |> take(1)
    |> deliverOnMainQueue).start(next: { [weak controller] result in
        var peerIds: [ContactListPeerId] = []
        if case let .result(peerIdsValue, _) = result {
            peerIds = peerIdsValue
        }
        completion(peerIds.compactMap { entry -> Int64? in
            if case let .peer(value) = entry {
                return value.toInt64()
            }
            return nil
        })
        controller?.dismiss()
    })

    parentController.push(controller)
}

/// The action picker. A screen of its own rather than a menu: ten options do not fit a
/// context menu, and this is the same shape every other Netegram sub-screen uses.
private func netegramFakeKindController(context: AccountContext) -> ViewController {
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramFakePreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = NetegramFakeActivityKind.allCases.enumerated().map { index, kind in
            NetegramFakeKindEntry(index: Int32(index), kind: kind, checked: kind == settings.kind)
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramFakeStrings.activityKind),
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

        return (controllerState, (listState, NetegramFakeKindArguments()))
    }

    return ItemListController(context: context, state: signal)
}

private final class NetegramFakeKindArguments {
}

private struct NetegramFakeKindEntry: ItemListNodeEntry {
    let index: Int32
    let kind: NetegramFakeActivityKind
    let checked: Bool

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return self.index
    }

    static func <(lhs: NetegramFakeKindEntry, rhs: NetegramFakeKindEntry) -> Bool {
        return lhs.index < rhs.index
    }

    static func ==(lhs: NetegramFakeKindEntry, rhs: NetegramFakeKindEntry) -> Bool {
        return lhs.index == rhs.index && lhs.kind == rhs.kind && lhs.checked == rhs.checked
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let kind = self.kind
        return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: kind.title, style: .right, checked: self.checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
            NetegramFakePreferences.shared.setActivityKind(kind)
        })
    }
}

public func netegramFakeActivityController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentPeerPickerImpl: (([Int64], @escaping ([Int64]) -> Void) -> Void)?

    let arguments = NetegramFakeArguments(updateActivityEnabled: { value in
        NetegramFakePreferences.shared.setActivityEnabled(value)
    }, openKind: {
        pushControllerImpl?(netegramFakeKindController(context: context))
    }, openActivityPeers: {
        presentPeerPickerImpl?(NetegramFakePreferences.current().activityPeers, { peerIds in
            NetegramFakePreferences.shared.setActivityPeers(peerIds)
        })
    }, updateReadEnabled: { value in
        NetegramFakePreferences.shared.setReadEnabled(value)
    }, openReadPeers: {
        presentPeerPickerImpl?(NetegramFakePreferences.current().readPeers, { peerIds in
            NetegramFakePreferences.shared.setReadPeers(peerIds)
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramFakePreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [NetegramFakeEntry] = [
            .activityHeader,
            .activityEnabled(settings.activityEnabled),
            .activityKind(settings.kind.title, settings.activityEnabled),
            .activityPeers(settings.activityPeers.count, settings.activityEnabled),
            .activityFooter,
            .readHeader,
            .readEnabled(settings.readEnabled),
            .readPeers(settings.readPeers.count, settings.readEnabled),
            .readFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramFakeStrings.title),
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
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentPeerPickerImpl = { [weak controller] selected, completion in
        guard let controller else {
            return
        }
        netegramPresentPeerPicker(context: context, selected: selected, parentController: controller, completion: completion)
    }
    return controller
}
