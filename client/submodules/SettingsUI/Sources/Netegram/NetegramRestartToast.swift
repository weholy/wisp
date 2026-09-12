import Foundation
import Display
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import UndoUI

/// Netegram: copy for the "restart to apply" notices.
public enum NetegramRestartStrings {
    public static let glass = "Перезапустите Netegram — стекло встанет на все экраны."
    public static let contextMenu = "Перезапустите Netegram, чтобы меню сообщений пересобралось."
    public static let profileButtons = "Перезапустите Netegram, чтобы кнопки профиля перерисовались."
    public static let background = "Перезапустите Netegram, чтобы фон встал позади всех экранов."
    public static let navBar = "Перезапустите Netegram, чтобы нижняя панель пересобралась."
    public static let ads = "Перезапустите Netegram — уже загруженная реклама исчезнет вместе с ней."
}

/// Shows the restart notice as the rounded bar at the bottom of the screen.
///
/// A modal alert stops the user mid-thought to say something they cannot act on right now;
/// these settings keep working while the notice is up, so it belongs in the passive slot the
/// app already uses for "done, but there is a caveat" messages.
///
/// Not every toggle gets one — only those whose effect is cached at launch or baked into an
/// already-built screen. Settings that repaint immediately would just be nagging.
public func netegramPresentRestartToast(context: AccountContext, controller: ViewController?, text: String) {
    guard let controller else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller.present(
        UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            action: { _ in return false }
        ),
        in: .current
    )
}
