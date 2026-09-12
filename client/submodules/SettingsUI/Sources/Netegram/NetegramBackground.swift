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

public enum NetegramBackgroundStrings {
    public static let title = "Фон приложения"
    public static let videoTitle = "Видео-фон"
    public static let videoFooter = "Видео проигрывается позади всех экранов. Интерфейс становится полупрозрачным, чтобы фон был виден."
    public static let photoTitle = "Фото-фон"
    public static let photoFooter = "Изображение позади всех экранов. Расходует заметно меньше батареи, чем видео."
    public static let choose = "Выбрать из галереи"
    public static let chosen = "Выбрано"
}

private let backgroundModeKey = "netegram.background.mode"
private let backgroundPathKey = "netegram.background.path"

/// Which background the client draws behind every screen.
public enum NetegramBackgroundMode: Int32 {
    case none = 0
    case photo = 1
    case video = 2
}

public struct NetegramBackgroundState: Equatable {
    public let mode: NetegramBackgroundMode
    public let path: String

    public init(mode: NetegramBackgroundMode, path: String) {
        self.mode = mode
        self.path = path
    }

    public var hasMedia: Bool {
        return !self.path.isEmpty
    }
}

/// Device-local background settings.
///
/// Photo and video are mutually exclusive: one background layer is drawn, so turning one on
/// turns the other off rather than leaving two conflicting sources selected.
public final class NetegramBackgroundSettings {
    public static let shared = NetegramBackgroundSettings()

    private let promise: ValuePromise<NetegramBackgroundState>

    private init() {
        self.promise = ValuePromise(NetegramBackgroundSettings.current(), ignoreRepeated: true)
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.promise.set(NetegramBackgroundSettings.current())
    }

    public static func current() -> NetegramBackgroundState {
        let rawMode = Int32(NGStore.integer(forKey: backgroundModeKey))
        return NetegramBackgroundState(
            mode: NetegramBackgroundMode(rawValue: rawMode) ?? .none,
            path: NGStore.string(forKey: backgroundPathKey) ?? ""
        )
    }

    public var signal: Signal<NetegramBackgroundState, NoError> {
        return self.promise.get()
    }

    public func setMode(_ mode: NetegramBackgroundMode) {
        NGStore.setObject(Int(mode.rawValue), forKey: backgroundModeKey)
        self.promise.set(NetegramBackgroundSettings.current())
    }

    public func setPath(_ path: String) {
        NGStore.setObject(path, forKey: backgroundPathKey)
        self.promise.set(NetegramBackgroundSettings.current())
    }
}

// MARK: - Picking the media

/// Holds the picker's delegate alive.
///
/// UIImagePickerController keeps only a weak reference to its delegate, so without this the
/// delegate is released the moment the presenting call returns and the picked file is lost.
private final class NetegramBackgroundPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private static var current: NetegramBackgroundPicker?

    private let completion: (String?) -> Void

    private init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    static func present(window: Window1?, mode: NetegramBackgroundMode, completion: @escaping (String?) -> Void) {
        guard let window else {
            completion(nil)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = mode == .video ? ["public.movie"] : ["public.image"]
        // Editing would hand back a cropped copy in a temporary location; the background is
        // drawn aspect-filled anyway, so the original is what we want.
        picker.allowsEditing = false

        let delegate = NetegramBackgroundPicker(completion: completion)
        NetegramBackgroundPicker.current = delegate
        picker.delegate = delegate

        window.presentNative(picker)
    }

    private func finish(_ picker: UIImagePickerController, fileName: String?) {
        picker.presentingViewController?.dismiss(animated: true)
        NetegramBackgroundPicker.current = nil
        self.completion(fileName)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.finish(picker, fileName: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let sourceURL = (info[.mediaURL] as? URL) ?? (info[.imageURL] as? URL)
        guard let sourceURL else {
            self.finish(picker, fileName: nil)
            return
        }
        self.finish(picker, fileName: netegramStoreBackgroundMedia(from: sourceURL))
    }
}

/// Copies the picked file into the app's documents directory and returns its file name.
///
/// Only the name is stored: the app container is re-rooted on every reinstall, so an absolute
/// path saved today stops resolving tomorrow. The name carries a timestamp because the
/// renderer caches by path — reusing one name would keep showing the previous file.
private func netegramStoreBackgroundMedia(from sourceURL: URL) -> String? {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return nil
    }

    let previous = NetegramBackgroundSettings.current().path
    if !previous.isEmpty {
        try? FileManager.default.removeItem(at: documents.appendingPathComponent(previous))
    }

    let fileExtension = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
    let fileName = "netegram-background-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
    do {
        try FileManager.default.copyItem(at: sourceURL, to: documents.appendingPathComponent(fileName))
    } catch {
        return nil
    }
    return fileName
}

private func netegramPickBackgroundMedia(context: AccountContext, mode: NetegramBackgroundMode, completion: @escaping (String?) -> Void) {
    NetegramBackgroundPicker.present(window: context.sharedContext.mainWindow, mode: mode, completion: completion)
}

// MARK: - Screen

private final class NetegramBackgroundArguments {
    let updateVideo: (Bool) -> Void
    let updatePhoto: (Bool) -> Void
    let choose: (NetegramBackgroundMode) -> Void

    init(updateVideo: @escaping (Bool) -> Void, updatePhoto: @escaping (Bool) -> Void, choose: @escaping (NetegramBackgroundMode) -> Void) {
        self.updateVideo = updateVideo
        self.updatePhoto = updatePhoto
        self.choose = choose
    }
}

private enum NetegramBackgroundSection: Int32 {
    case video
    case photo
}

private enum NetegramBackgroundEntry: ItemListNodeEntry {
    case video(Bool)
    case chooseVideo(String)
    case videoFooter
    case photo(Bool)
    case choosePhoto(String)
    case photoFooter

    /// The picker row shares its toggle's section so the two are drawn in one rounded block.
    var section: ItemListSectionId {
        switch self {
        case .video, .chooseVideo, .videoFooter:
            return NetegramBackgroundSection.video.rawValue
        case .photo, .choosePhoto, .photoFooter:
            return NetegramBackgroundSection.photo.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .video:
            return 0
        case .chooseVideo:
            return 1
        case .videoFooter:
            return 2
        case .photo:
            return 3
        case .choosePhoto:
            return 4
        case .photoFooter:
            return 5
        }
    }

    static func <(lhs: NetegramBackgroundEntry, rhs: NetegramBackgroundEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NetegramBackgroundArguments
        switch self {
        case let .video(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramBackgroundStrings.videoTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateVideo(value)
            })
        case .videoFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramBackgroundStrings.videoFooter), sectionId: self.section)
        case let .photo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: NetegramBackgroundStrings.photoTitle, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updatePhoto(value)
            })
        case .photoFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(NetegramBackgroundStrings.photoFooter), sectionId: self.section)
        case let .chooseVideo(current):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramBackgroundStrings.choose, label: current, sectionId: self.section, style: .blocks, action: {
                arguments.choose(.video)
            })
        case let .choosePhoto(current):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: NetegramBackgroundStrings.choose, label: current, sectionId: self.section, style: .blocks, action: {
                arguments.choose(.photo)
            })
        }
    }
}

/// The picker row only appears once a mode is on, and directly under the toggle that turned
/// it on — the two belong to the same decision, so they read as one block.
private func netegramBackgroundEntries(state: NetegramBackgroundState) -> [NetegramBackgroundEntry] {
    let label = state.hasMedia ? NetegramBackgroundStrings.chosen : ""
    var entries: [NetegramBackgroundEntry] = [.video(state.mode == .video)]
    if state.mode == .video {
        entries.append(.chooseVideo(label))
    }
    entries.append(.videoFooter)
    entries.append(.photo(state.mode == .photo))
    if state.mode == .photo {
        entries.append(.choosePhoto(label))
    }
    entries.append(.photoFooter)
    return entries
}

public func netegramBackgroundController(context: AccountContext) -> ViewController {
    var presentRestartImpl: (() -> Void)?

    let arguments = NetegramBackgroundArguments(updateVideo: { value in
        NetegramBackgroundSettings.shared.setMode(value ? .video : .none)
        // Only worth mentioning a restart when there is actually something to draw.
        if NetegramBackgroundSettings.current().hasMedia {
            presentRestartImpl?()
        }
    }, updatePhoto: { value in
        // Only one background layer is drawn, so enabling one mode disables the other.
        NetegramBackgroundSettings.shared.setMode(value ? .photo : .none)
        if NetegramBackgroundSettings.current().hasMedia {
            presentRestartImpl?()
        }
    }, choose: { mode in
        netegramPickBackgroundMedia(context: context, mode: mode, completion: { fileName in
            guard let fileName else {
                return
            }
            NetegramBackgroundSettings.shared.setPath(fileName)
            presentRestartImpl?()
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        NetegramBackgroundSettings.shared.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(NetegramBackgroundStrings.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: netegramBackgroundEntries(state: state),
            style: .blocks,
            animateChanges: true
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentRestartImpl = { [weak controller] in
        netegramPresentRestartToast(context: context, controller: controller, text: NetegramRestartStrings.background)
    }
    return controller
}
