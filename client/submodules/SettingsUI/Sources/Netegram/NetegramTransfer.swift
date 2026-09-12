import Foundation
import NetegramStore
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

public enum NetegramTransferStrings {
    public static let title = "Перенос настроек"
    public static let subtitle = "Экспорт, импорт, сброс"

    public static let export = "Экспортировать"
    public static let exportFooter = "Сохраняет настройки Netegram в файл."
    public static let importTitle = "Импортировать"
    public static let importFooter = "Загружает настройки из такого файла."
    public static let reset = "Сбросить всё"
    public static let resetFooter = "Возвращает настройки Netegram по умолчанию. Чаты и аккаунт не трогаются."
    public static let resetConfirm = "Сбросить все настройки Netegram?"

    public static let exported = "Настройки собраны"
    public static let imported = "Настройки загружены. Перезапустите приложение."
    public static let importFailed = "Это не файл настроек Netegram."
    public static let didReset = "Настройки сброшены. Перезапустите Netegram."
}

/// Netegram: reading and writing every setting this fork owns, as one JSON document.
///
/// Everything lives under the `netegram.` prefix in NGStore, which makes the set easy to walk
/// without keeping a list that would drift out of date every time a switch is added.
public enum NetegramTransfer {
    /// Bumped if the shape ever changes, so an old file can be recognised rather than
    /// half-applied.
    private static let formatVersion = 1

    /// The document handed to the share sheet.
    public static func exportData() -> Data? {
        let document: [String: Any] = [
            "format": NetegramTransfer.formatVersion,
            "app": "Netegram",
            "exportedAt": Int(Date().timeIntervalSince1970),
            "settings": NGStore.allValues()
        ]
        return try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    /// Applies a previously exported document. Returns false when the file is not one of ours.
    ///
    /// Keys outside our prefix are ignored rather than trusted: an imported file must not be
    /// able to reach into Telegram's own preferences. NGStore enforces that itself, so a file
    /// carrying junk alongside our keys still applies the part that belongs to us.
    @discardableResult
    public static func importData(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let document = object as? [String: Any],
            let settings = document["settings"] as? [String: Any],
            document["app"] as? String == "Netegram"
        else {
            return false
        }

        NGStore.applyValues(settings)
        NetegramTransfer.republishSettings()
        return true
    }

    public static func reset() {
        NGStore.removeAllValues()
        NetegramTransfer.republishSettings()
    }

    /// Pushes the freshly loaded values into everything holding a copy in memory.
    ///
    /// Writing the keys is only half of an import. The screens read their state from
    /// `ValuePromise`s, and the surfaces that draw glass or a local override keep a cached
    /// copy so layout never reaches the store — none of which notice a value that changed
    /// underneath them. That is why importing a file used to appear to do nothing until the
    /// app was restarted.
    ///
    /// The caches observe `NGStore.didChangeNotification`, which the store has already posted
    /// by this point; what is left is the promises this module owns.
    private static func republishSettings() {
        NetegramSettings.shared.republish()
        NetegramLocalFeatures.shared.republish()
        NetegramGhostPreferences.shared.republish()
        NetegramLookPreferences.shared.republish()
        NetegramBackgroundSettings.shared.republish()
        NetegramAnnouncementSettings.shared.republish()
        NetegramFakePreferences.shared.republish()
    }

    /// Written to a temporary file because the share sheet hands other apps a URL, not bytes.
    public static func writeTemporaryFile() -> URL? {
        guard let data = NetegramTransfer.exportData() else {
            return nil
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("netegram-settings.json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }
}

/// Keeps the document picker's delegate alive; the picker holds only a weak reference.
private final class NetegramSettingsFilePicker: NSObject, UIDocumentPickerDelegate {
    private static var current: NetegramSettingsFilePicker?

    private let completion: (Data?) -> Void

    private init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    static func present(window: Window1?, completion: @escaping (Data?) -> Void) {
        guard let window else {
            completion(nil)
            return
        }
        // The project still targets iOS 13, where this initialiser does not exist yet. The
        // older one is deprecated and would fail the module's warnings-as-errors, so the
        // feature simply is not offered on 13 rather than being written twice.
        guard #available(iOS 14.0, *) else {
            completion(nil)
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        let delegate = NetegramSettingsFilePicker(completion: completion)
        NetegramSettingsFilePicker.current = delegate
        picker.delegate = delegate
        window.presentNative(picker)
    }

    private func finish(_ data: Data?) {
        NetegramSettingsFilePicker.current = nil
        self.completion(data)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            self.finish(nil)
            return
        }
        self.finish(try? Data(contentsOf: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.finish(nil)
    }
}

private final class NetegramTransferArguments {
    let exportSettings: () -> Void
    let importSettings: () -> Void
    let resetSettings: () -> Void

    init(exportSettings: @escaping () -> Void, importSettings: @escaping () -> Void, resetSettings: @escaping () -> Void) {
        self.exportSettings = exportSettings
        self.importSettings = importSettings
        self.resetSettings = resetSettings
    }
}

private enum NetegramTransferEntry: ItemListNodeEntry {
    case export
    case exportFooter
    case importSettings
    case importFooter
    case reset
    case resetFooter

    /// One section per action, so each sits in its own block with its caption underneath.
    var section: ItemListSectionId {
        switch self {
        case .export, .exportFooter:
            return 0
        case .importSettings, .importFooter:
            return 1
        case .reset, .resetFooter:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .export: return 0
        case .exportFooter: return 1
        case .importSettings: return 2
        case .importFooter: return 3
        case .reset: return 4
        case .resetFooter: return 5
        }
    }

    static func <(lhs: NetegramTransferEntry, rhs: NetegramTransferEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramTransferArguments
        switch self {
        case .export:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: NetegramTransferStrings.export, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportSettings()
            })
        case .exportFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramTransferStrings.exportFooter), sectionId: self.section)
        case .importSettings:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: NetegramTransferStrings.importTitle, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importSettings()
            })
        case .importFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramTransferStrings.importFooter), sectionId: self.section)
        case .reset:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: NetegramTransferStrings.reset, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetSettings()
            })
        case .resetFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramTransferStrings.resetFooter), sectionId: self.section)
        }
    }
}

private func netegramTransferEntries() -> [NetegramTransferEntry] {
    return [.export, .exportFooter, .importSettings, .importFooter, .reset, .resetFooter]
}

public func netegramTransferController(context: AccountContext) -> ViewController {
    var presentToastImpl: ((String) -> Void)?
    var presentShareImpl: ((URL) -> Void)?
    var presentResetConfirmImpl: (() -> Void)?

    let arguments = NetegramTransferArguments(exportSettings: {
        guard let url = NetegramTransfer.writeTemporaryFile() else {
            return
        }
        presentShareImpl?(url)
    }, importSettings: {
        NetegramSettingsFilePicker.present(window: context.sharedContext.mainWindow, completion: { data in
            guard let data else {
                return
            }
            if NetegramTransfer.importData(data) {
                presentToastImpl?(NetegramTransferStrings.imported)
            } else {
                presentToastImpl?(NetegramTransferStrings.importFailed)
            }
        })
    }, resetSettings: {
        presentResetConfirmImpl?()
    })

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramTransferStrings.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: netegramTransferEntries(),
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    presentToastImpl = { [weak controller] text in
        netegramPresentRestartToast(context: context, controller: controller, text: text)
    }
    presentShareImpl = { [weak controller] url in
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Anchored on iPad, where a sheet without a source is a crash rather than a sheet.
        if let controller {
            share.popoverPresentationController?.sourceView = controller.view
            share.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1.0, height: 1.0)
        }
        context.sharedContext.mainWindow?.presentNative(share)
    }
    presentResetConfirmImpl = { [weak controller] in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(
            textAlertController(context: context, title: nil, text: NetegramTransferStrings.resetConfirm, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: NetegramTransferStrings.reset, action: {
                    NetegramTransfer.reset()
                    presentToastImpl?(NetegramTransferStrings.didReset)
                })
            ]),
            in: .window(.root)
        )
    }

    return controller
}
