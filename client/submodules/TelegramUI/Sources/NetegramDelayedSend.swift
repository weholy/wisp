import Foundation
import UIKit
import Display
import SwiftSignalKit
import MtProtoKit
import TelegramPresentationData
import AccountContext
import UndoUI

/// Netegram: the "cancel" offer shown while a message is held back.
///
/// The delay is enforced down in MTProtoKit, which has no way to put anything on screen. It
/// posts a notification instead, and this listens for it — the alternative would be threading
/// a UI callback through the whole network stack for one button.
///
/// Notices are coalesced: sending three messages in a row should not stack three bars, and one
/// cancel drops every send still waiting anyway.
public final class NetegramDelayedSendNotice {
    public static let shared = NetegramDelayedSendNotice()

    private weak var context: AccountContext?
    private var isShowing = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.sendStarted(_:)),
            // The bridge both retypes the constant as NSNotification.Name and strips the
            // "Notification" suffix from its name, so this is the same constant declared in
            // MTNetegramGhost.h under the name Swift gives it.
            name: NSNotification.Name.MTNetegramDelayedSendStarted,
            object: nil
        )
    }

    public func setContext(_ context: AccountContext) {
        self.context = context
    }

    @objc private func sendStarted(_ notification: Notification) {
        Queue.mainQueue().async { [weak self] in
            guard let self, let context = self.context, !self.isShowing else {
                return
            }
            guard let controller = context.sharedContext.mainWindow?.viewController as? ViewController else {
                return
            }

            let seconds = (notification.userInfo?["delay"] as? Double) ?? 5.0
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }

            self.isShowing = true
            controller.present(
                UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(
                        title: nil,
                        text: "Отправка через \(Int(seconds)) с",
                        timeout: seconds,
                        customUndoText: "Отменить"
                    ),
                    elevatedLayout: false,
                    action: { [weak self] action in
                        if case .undo = action {
                            MTNetegramGhost.cancelDelayedSends()
                        }
                        self?.isShowing = false
                        return true
                    }
                ),
                in: .window(.root)
            )

            // The action callback does not always fire — a bar that expires quietly leaves it
            // unset — so the flag is released on a timer as well, or the next send would find
            // a notice still marked as showing and stay silent.
            Queue.mainQueue().after(seconds + 1.0) { [weak self] in
                self?.isShowing = false
            }
        }
    }
}
