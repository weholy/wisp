import Foundation
import NetegramStore
import UIKit
import AVFoundation

/// Netegram: the photo or video drawn behind every screen.
///
/// Keys are mirrored from NetegramBackground in SettingsUI. Only the file name is stored, not
/// a full path: the app container is re-rooted on every reinstall, so an absolute path saved
/// today stops resolving tomorrow.
private let backgroundModeKey = "netegram.background.mode"
private let backgroundPathKey = "netegram.background.path"

/// Where the chosen file is kept. Mirrored in SettingsUI, which writes into it.
public func netegramBackgroundFileURL(fileName: String) -> URL? {
    guard !fileName.isEmpty else {
        return nil
    }
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return nil
    }
    return documents.appendingPathComponent(fileName)
}

public final class NetegramAppBackgroundView: UIView {
    private var imageView: UIImageView?
    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.clipsToBounds = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    /// Puts the background underneath the app's content. Returns true if anything is drawn,
    /// so the caller knows whether the container still needs its opaque fill.
    @discardableResult
    public static func install(in containerView: UIView) -> Bool {
        let mode = NGStore.integer(forKey: backgroundModeKey)
        let fileName = NGStore.string(forKey: backgroundPathKey) ?? ""
        guard mode != 0, let url = netegramBackgroundFileURL(fileName: fileName), FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let view = NetegramAppBackgroundView(frame: containerView.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Photo is 1, video is 2 — matching NetegramBackgroundMode.
        if mode == 2 {
            view.setUpVideo(url: url)
        } else {
            view.setUpImage(url: url)
        }
        containerView.insertSubview(view, at: 0)
        // Inserting at the bottom is not enough: the window puts the root controller's view in
        // at index zero later, which pushes this one above it and lands the background on top
        // of the whole interface. A negative depth keeps it behind whatever the order becomes.
        view.layer.zPosition = -1000.0
        return true
    }

    private func setUpImage(url: URL) {
        let imageView = UIImageView(image: UIImage(contentsOfFile: url.path))
        imageView.contentMode = .scaleAspectFill
        imageView.frame = self.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(imageView)
        self.imageView = imageView
    }

    private func setUpVideo(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        // Muted so the background never competes with voice messages or calls, and so it does
        // not take over the audio session.
        player.isMuted = true
        player.actionAtItemEnd = .advance

        self.looper = AVPlayerLooper(player: player, templateItem: item)

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = self.bounds
        self.layer.addSublayer(playerLayer)

        self.player = player
        self.playerLayer = playerLayer
        player.play()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // The layer is not a subview, so autoresizing does not reach it.
        self.playerLayer?.frame = self.bounds
    }

    @objc private func applicationDidBecomeActive() {
        self.player?.play()
    }

    @objc private func applicationWillResignActive() {
        // A video decoding behind a backgrounded app is pure battery cost.
        self.player?.pause()
    }
}
