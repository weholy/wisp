import Foundation
import UIKit
import CoreLocation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class NetegramGhostArguments {
    let updateFlag: (String, Bool) -> Void
    let updateDelaySeconds: (Int32) -> Void
    let updateDeviceName: (String) -> Void
    let pickLocation: () -> Void
    let resetLocation: () -> Void

    init(updateFlag: @escaping (String, Bool) -> Void, updateDelaySeconds: @escaping (Int32) -> Void, updateDeviceName: @escaping (String) -> Void, pickLocation: @escaping () -> Void, resetLocation: @escaping () -> Void) {
        self.updateFlag = updateFlag
        self.updateDelaySeconds = updateDelaySeconds
        self.updateDeviceName = updateDeviceName
        self.pickLocation = pickLocation
        self.resetLocation = resetLocation
    }
}

/// Every switch gets its own section, so it is drawn as its own rounded block with the
/// explanation underneath it rather than crowded together with unrelated settings.
///
/// Sections are numbered from the row's position in `netegramGhostRows`; the extras that follow
/// take numbers above them. Adding a switch means adding one line to that list and nothing
/// here — which is the point of building the screen from data instead of from cases.
private enum NetegramGhostSection {
    static let extraBase: Int32 = 1000
}

private enum NetegramGhostEntry: ItemListNodeEntry {
    /// index, key, title, value, enabled
    case toggle(Int32, String, String, Bool, Bool)
    /// index, footer text
    case toggleFooter(Int32, String)

    case delaySeconds(Int32, Bool)
    case locationPick(String)
    case locationReset
    case deviceName(String)
    case deviceNameFooter

    var section: ItemListSectionId {
        switch self {
        case let .toggle(index, _, _, _, _), let .toggleFooter(index, _):
            return ItemListSectionId(index)
        case .delaySeconds:
            return ItemListSectionId(NetegramGhostSection.extraBase)
        case .locationPick, .locationReset:
            return ItemListSectionId(NetegramGhostSection.extraBase + 1)
        case .deviceName, .deviceNameFooter:
            return ItemListSectionId(NetegramGhostSection.extraBase + 2)
        }
    }

    var stableId: Int32 {
        switch self {
        // Two slots per row: the switch and the text under it.
        case let .toggle(index, _, _, _, _):
            return index * 2
        case let .toggleFooter(index, _):
            return index * 2 + 1
        case .delaySeconds:
            return NetegramGhostSection.extraBase
        case .locationPick:
            return NetegramGhostSection.extraBase + 1
        case .locationReset:
            return NetegramGhostSection.extraBase + 2
        case .deviceName:
            return NetegramGhostSection.extraBase + 3
        case .deviceNameFooter:
            return NetegramGhostSection.extraBase + 4
        }
    }

    static func <(lhs: NetegramGhostEntry, rhs: NetegramGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramGhostArguments
        switch self {
        case let .toggle(_, key, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateFlag(key, value)
            })
        case let .toggleFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .delaySeconds(value, enabled):
            return NetegramStarsSliderItem(theme: presentationData.theme, title: "\(NetegramGhostStrings.delayedSendSeconds): \(value) с", value: Int(value), maxValue: 60, enabled: enabled, sectionId: self.section, updated: { updated in
                arguments.updateDelaySeconds(Int32(max(1, updated)))
            })
        case let .locationPick(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramGhostStrings.locationPick, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pickLocation()
            })
        case .locationReset:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: NetegramGhostStrings.locationReset, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetLocation()
            })
        case let .deviceName(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: NetegramGhostStrings.deviceName, textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: NetegramGhostStrings.deviceNamePlaceholder, type: .regular(capitalization: true, autocorrection: false), sectionId: self.section, textUpdated: { value in
                arguments.updateDeviceName(value)
            }, action: {})
        case .deviceNameFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramGhostStrings.deviceNameFooter), sectionId: self.section)
        }
    }
}

private func netegramGhostEntries(settings: NetegramGhostSettings) -> [NetegramGhostEntry] {
    var entries: [NetegramGhostEntry] = []

    for (index, row) in netegramGhostRows.enumerated() {
        // "Читать при действиях" refines the switch above it and means nothing on its own.
        let enabled: Bool
        if row.key == NetegramGhostKeys.readOnAction {
            enabled = settings.flag(NetegramGhostKeys.readReceipts)
        } else {
            enabled = true
        }
        entries.append(.toggle(Int32(index), row.key, row.title, settings.flag(row.key), enabled))

        // The controls a switch owns sit inside its own block, above the explanation, so it is
        // obvious which switch they belong to.
        if row.key == NetegramGhostKeys.delayedSend {
            entries.append(.delaySeconds(settings.delayedSendSeconds, settings.flag(NetegramGhostKeys.delayedSend)))
        } else if row.key == NetegramGhostKeys.locationEnabled {
            entries.append(.locationPick(settings.hasLocation ? String(format: "%.4f, %.4f", settings.latitude, settings.longitude) : NetegramGhostStrings.locationNotSet))
            if settings.hasLocation {
                entries.append(.locationReset)
            }
        }

        entries.append(.toggleFooter(Int32(index), row.footer))
    }

    entries.append(.deviceName(settings.deviceName))
    entries.append(.deviceNameFooter)

    return entries
}

public func netegramGhostController(context: AccountContext) -> ViewController {
    let arguments = NetegramGhostArguments(updateFlag: { key, value in
        NetegramGhostPreferences.shared.setFlag(key, value: value)
    }, updateDelaySeconds: { value in
        NetegramGhostPreferences.shared.setDelayedSendSeconds(value)
    }, updateDeviceName: { value in
        NetegramGhostPreferences.shared.setDeviceName(value)
    }, pickLocation: {
        let current = NetegramGhostPreferences.current()
        let initial = current.hasLocation ? CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude) : nil
        netegramPresentLocationPicker(window: context.sharedContext.mainWindow, initial: initial, completion: { coordinate in
            NetegramGhostPreferences.shared.setLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        })
    }, resetLocation: {
        NetegramGhostPreferences.shared.resetLocation()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramGhostPreferences.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramGhostStrings.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: netegramGhostEntries(settings: settings),
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
