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

private final class NetegramSettingsControllerArguments {
    let openHideButtons: () -> Void
    let openNavBar: () -> Void
    let openLiquidGlass: () -> Void
    let openGhost: () -> Void
    let openLocalFeatures: () -> Void
    let openAutoFormat: () -> Void
    let openFakeActivity: () -> Void
    let openTransfer: () -> Void

    init(openHideButtons: @escaping () -> Void, openNavBar: @escaping () -> Void, openLiquidGlass: @escaping () -> Void, openGhost: @escaping () -> Void, openLocalFeatures: @escaping () -> Void, openAutoFormat: @escaping () -> Void, openFakeActivity: @escaping () -> Void, openTransfer: @escaping () -> Void) {
        self.openHideButtons = openHideButtons
        self.openNavBar = openNavBar
        self.openLiquidGlass = openLiquidGlass
        self.openGhost = openGhost
        self.openLocalFeatures = openLocalFeatures
        self.openAutoFormat = openAutoFormat
        self.openFakeActivity = openFakeActivity
        self.openTransfer = openTransfer
    }
}

// One section per row: rows sharing a section are drawn inside a single rounded block, so
// each entry needs its own to stand apart.
private enum NetegramSettingsSection: Int32 {
    case logoHeader
    case hideButtons
    case navBar
    case liquidGlass
    case ghost
    case localFeatures
    case autoFormat
    case fakeActivity
    case transfer
}

private enum NetegramSettingsEntry: ItemListNodeEntry {
    case logoHeader(Bool)
    case hideButtons
    case navBar
    case liquidGlass
    case ghost
    case localFeatures
    case autoFormat
    case fakeActivity
    case transfer

    var section: ItemListSectionId {
        switch self {
        case .logoHeader:
            return NetegramSettingsSection.logoHeader.rawValue
        case .hideButtons:
            return NetegramSettingsSection.hideButtons.rawValue
        case .navBar:
            return NetegramSettingsSection.navBar.rawValue
        case .liquidGlass:
            return NetegramSettingsSection.liquidGlass.rawValue
        case .ghost:
            return NetegramSettingsSection.ghost.rawValue
        case .localFeatures:
            return NetegramSettingsSection.localFeatures.rawValue
        case .autoFormat:
            return NetegramSettingsSection.autoFormat.rawValue
        case .fakeActivity:
            return NetegramSettingsSection.fakeActivity.rawValue
        case .transfer:
            return NetegramSettingsSection.transfer.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .logoHeader:
            return -1
        case .ghost:
            return 3
        case .liquidGlass:
            return 4
        case .hideButtons:
            return 5
        case .navBar:
            return 6
        case .localFeatures:
            return 7
        case .autoFormat:
            return 8
        case .fakeActivity:
            return 2
        case .transfer:
            return 9
        }
    }

    static func <(lhs: NetegramSettingsEntry, rhs: NetegramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramSettingsControllerArguments
        switch self {
        case let .logoHeader(showsRevision):
            return NetegramHeaderItem(theme: presentationData.theme, showsRevision: showsRevision, sectionId: self.section)
        case .hideButtons:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramLookStrings.hideButtonsTitle, label: "", additionalDetailLabel: NetegramLookStrings.hideButtonsSubtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openHideButtons()
            })
        // On this screen the description belongs inside the cell, under the title. The
        // screens these rows lead to keep their descriptions under the block instead.
        case .liquidGlass:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramStrings.liquidGlass, label: "", additionalDetailLabel: "Жидкое стекло в интерфейсе", sectionId: self.section, style: .blocks, action: {
                arguments.openLiquidGlass()
            })
        case .navBar:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramLookStrings.navBarTitle, label: "", additionalDetailLabel: NetegramLookStrings.navBarSubtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openNavBar()
            })
        case .ghost:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramGhostStrings.title, label: "", additionalDetailLabel: NetegramGhostStrings.subtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openGhost()
            })
        case .localFeatures:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramLocalStrings.localFeatures, label: "", additionalDetailLabel: "Премиум, звёзды, значки", sectionId: self.section, style: .blocks, action: {
                arguments.openLocalFeatures()
            })
        case .autoFormat:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramAutoFormatStrings.title, label: "", additionalDetailLabel: NetegramAutoFormatStrings.subtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openAutoFormat()
            })
        case .fakeActivity:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramFakeStrings.title, label: "", additionalDetailLabel: NetegramFakeStrings.subtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openFakeActivity()
            })
        case .transfer:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramTransferStrings.title, label: "", additionalDetailLabel: NetegramTransferStrings.subtitle, sectionId: self.section, style: .blocks, action: {
                arguments.openTransfer()
            })
        }
    }
}

/// The full, and now only, list. "Владелец" used to unlock four more screens — Внешний вид,
/// Фон приложения and Объявление — which are gone: their settings entry was the sole way to
/// reach or change them, so removing it retires the feature rather than merely hiding it.
private let netegramPublicEntries: [NetegramSettingsEntry] = [.ghost, .liquidGlass, .navBar]

private func netegramSettingsEntries(isOwner: Bool) -> [NetegramSettingsEntry] {
    guard isOwner else {
        return netegramPublicEntries
    }
    return [.logoHeader(true), .fakeActivity, .ghost, .liquidGlass, .hideButtons, .navBar, .localFeatures, .autoFormat, .transfer]
}

/// Netegram: the account this build belongs to.
///
/// Three ways to match, because none of them is reliable on its own — the peer id is empty
/// until the account loads, the username can be changed, and the phone number is hidden on
/// some accounts. Any one hit is enough.
public func netegramIsBuildOwner(peer: EnginePeer?) -> Bool {
    guard let peer else {
        return false
    }
    if peer.id.id._internalGetInt64Value() == netegramAnnouncementOwnerId {
        return true
    }
    if let username = peer.addressName, username.lowercased() == netegramOwnerUsername {
        return true
    }
    if case let .user(user) = peer, let phone = user.phone {
        if phone.filter({ $0.isNumber }) == netegramOwnerPhone {
            return true
        }
    }
    return false
}

private let netegramOwnerUsername = "detarlo"
private let netegramOwnerPhone = "79809334541"

/// Retires the three removed screens' settings, one time, so nobody who had already turned one
/// on is left stuck with it permanently active and no menu path left to switch it back off.
private func netegramRetireRemovedScreens() {
    guard !NGStore.bool(forKey: "netegram.removedScreensRetired") else {
        return
    }
    NGStore.setObject(false, forKey: netegramContextRedesignKey)
    NGStore.setObject(false, forKey: netegramRoundProfileButtonsKey)
    NGStore.setObject(0, forKey: "netegram.background.mode")
    NGStore.setObject(true, forKey: "netegram.removedScreensRetired")
}

public func netegramSettingsController(context: AccountContext) -> ViewController {
    netegramRetireRemovedScreens()

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = NetegramSettingsControllerArguments(openHideButtons: {
        pushControllerImpl?(netegramHideProfileButtonsController(context: context))
    }, openNavBar: {
        pushControllerImpl?(netegramNavBarController(context: context))
    }, openLiquidGlass: {
        pushControllerImpl?(netegramLiquidGlassController(context: context))
    }, openGhost: {
        pushControllerImpl?(netegramGhostController(context: context))
    }, openLocalFeatures: {
        pushControllerImpl?(netegramLocalFeaturesController(context: context))
    }, openAutoFormat: {
        pushControllerImpl?(netegramAutoFormatController(context: context))
    }, openFakeActivity: {
        pushControllerImpl?(netegramFakeActivityController(context: context))
    }, openTransfer: {
        pushControllerImpl?(netegramTransferController(context: context))
    })

    let ownerSignal = context.engine.data.subscribe(
        TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)
    )
    |> map { peer -> Bool in
        return netegramIsBuildOwner(peer: peer)
    }
    |> distinctUntilChanged

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ownerSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, isOwner -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramStrings.netegram),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: netegramSettingsEntries(isOwner: isOwner),
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
