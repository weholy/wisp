import Foundation
import SwiftSignalKit
import NetegramStore

/// User-facing copy for the Netegram-specific screens.
///
/// These features do not exist in Telegram's server-delivered language packs, so the text
/// lives here instead of in Localizable.strings — otherwise every locale except English
/// would fall back to a missing key.
public enum NetegramStrings {
    public static let netegram = "Netegram"
    public static let liquidGlass = "Liquid Glass"
    public static let liquidGlassMessagesTitle = "Liquid Glass на сообщения"
    public static let liquidGlassMessagesFooter = "Прозрачные пузырьки сообщений."
    public static let liquidGlassInlineButtonsTitle = "Liquid Glass на кнопки ботов"
    public static let liquidGlassInlineButtonsFooter = "Стеклянные кнопки у ботов."
    public static let liquidGlassInputPanelTitle = "Liquid Glass на поле ввода"
    public static let liquidGlassInputPanelFooter = "Стеклянное поле ввода."
    public static let liquidGlassTabBarTitle = "Liquid Glass на нижнюю панель"
    public static let liquidGlassTabBarFooter = "Стеклянная нижняя панель."
}

/// State of the Liquid Glass toggles.
///
/// Four surfaces, each with its own switch and nothing that reaches past them. The blanket
/// "everywhere" switch and the chat-list header one were removed: the first painted glass on
/// surfaces that were never designed for it, and both overlapped the four below in ways that
/// made a single toggle's effect impossible to predict.
///
/// A struct rather than a tuple: ValuePromise requires Equatable, and Swift tuples do not
/// conform to it however simple their elements are.
public struct NetegramLiquidGlassSettings: Equatable {
    public let messages: Bool
    public let inlineButtons: Bool
    public let inputPanel: Bool
    public let tabBar: Bool

    public init(messages: Bool, inlineButtons: Bool, inputPanel: Bool, tabBar: Bool) {
        self.messages = messages
        self.inlineButtons = inlineButtons
        self.inputPanel = inputPanel
        self.tabBar = tabBar
    }
}

/// The app icon baked into the bundle as the primary icon (Netegram artwork). There is no
/// switch back to Telegram's own branding — Netegram's blue icon is the only one shipped.
public let netegramDefaultAppIconName = "NetegramIcon"

private let liquidGlassMessagesKey = "netegram.liquidGlass.messages"
/// Mirrored in ChatMessageActionButtonsNode, which cannot import this module (SettingsUI
/// depends on it, not the other way round) and so reads the key directly.
private let liquidGlassInlineButtonsKey = "netegram.liquidGlass.inlineButtons"
/// Mirrored in ChatTextInputPanelNode.
private let liquidGlassInputPanelKey = "netegram.liquidGlass.inputPanel"
/// Mirrored in TabBarComponent.
private let liquidGlassTabBarKey = "netegram.liquidGlass.tabBar"

/// Local, device-only Liquid Glass preferences.
///
/// Backed by NGStore rather than Postbox shared data: the value never syncs between devices
/// and is read during presentation, so the simpler store avoids threading a new preferences
/// key through the account schema.
public final class NetegramSettings {
    public static let shared = NetegramSettings()

    private let liquidGlassPromise: ValuePromise<NetegramLiquidGlassSettings>

    private init() {
        self.liquidGlassPromise = ValuePromise(NetegramSettings.currentLiquidGlass(), ignoreRepeated: true)
    }

    public var liquidGlassMessages: Bool {
        return NGStore.bool(forKey: liquidGlassMessagesKey)
    }

    public var liquidGlassSignal: Signal<NetegramLiquidGlassSettings, NoError> {
        return self.liquidGlassPromise.get()
    }

    public func setLiquidGlassMessages(_ value: Bool) {
        NGStore.setObject(value, forKey: liquidGlassMessagesKey)
        self.pushLiquidGlass()
    }

    public func setLiquidGlassInlineButtons(_ value: Bool) {
        NGStore.setObject(value, forKey: liquidGlassInlineButtonsKey)
        self.pushLiquidGlass()
    }

    public func setLiquidGlassInputPanel(_ value: Bool) {
        NGStore.setObject(value, forKey: liquidGlassInputPanelKey)
        self.pushLiquidGlass()
    }

    public func setLiquidGlassTabBar(_ value: Bool) {
        NGStore.setObject(value, forKey: liquidGlassTabBarKey)
        self.pushLiquidGlass()
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.pushLiquidGlass()
    }

    private func pushLiquidGlass() {
        self.liquidGlassPromise.set(NetegramSettings.currentLiquidGlass())
    }

    private static func currentLiquidGlass() -> NetegramLiquidGlassSettings {
        return NetegramLiquidGlassSettings(
            messages: NGStore.bool(forKey: liquidGlassMessagesKey),
            inlineButtons: NGStore.bool(forKey: liquidGlassInlineButtonsKey),
            inputPanel: NGStore.bool(forKey: liquidGlassInputPanelKey),
            tabBar: NGStore.bool(forKey: liquidGlassTabBarKey)
        )
    }
}
