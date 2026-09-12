import Foundation
import UIKit
import MapKit
import Display

/// Netegram: picks the coordinates reported instead of the real ones.
///
/// A plain MapKit screen rather than Telegram's own location picker: that one searches venues
/// and shares a place with someone, which is a different job — here nothing is sent anywhere,
/// the point is only to name a spot on the globe.
///
/// The pin is fixed to the centre of the screen and the map moves under it. Dropping an
/// annotation you then have to drag is fiddlier at the exact moment precision matters.
final class NetegramLocationPickerController: UIViewController {
    private let mapView = MKMapView()
    private let pinView = UIImageView()
    private let coordinateLabel = UILabel()
    private let initial: CLLocationCoordinate2D?
    private let completion: (CLLocationCoordinate2D) -> Void

    init(initial: CLLocationCoordinate2D?, completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.initial = initial
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NetegramGhostStrings.locationPickTitle
        self.view.backgroundColor = .systemBackground

        self.mapView.frame = self.view.bounds
        self.mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Explicit rather than relying on MKMapView's defaults: this screen has one job, and
        // a drag that silently does nothing is the single worst way for it to fail.
        self.mapView.isUserInteractionEnabled = true
        self.mapView.isScrollEnabled = true
        self.mapView.isZoomEnabled = true
        self.mapView.isPitchEnabled = false
        self.mapView.isRotateEnabled = false
        self.view.addSubview(self.mapView)

        // A coordinate is set even with nothing saved yet: MapKit's own unset region is a
        // near-global view, where a drag shifts the map by a fraction of a pixel and looks
        // exactly like the map not responding at all.
        let startingCoordinate = self.initial ?? CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        self.mapView.setRegion(MKCoordinateRegion(center: startingCoordinate, latitudinalMeters: 2000.0, longitudinalMeters: 2000.0), animated: false)

        self.pinView.image = UIImage(systemName: "mappin.and.ellipse")
        self.pinView.tintColor = .systemRed
        self.pinView.contentMode = .scaleAspectFit
        self.view.addSubview(self.pinView)

        self.coordinateLabel.textAlignment = .center
        self.coordinateLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .medium)
        self.coordinateLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        self.coordinateLabel.layer.cornerRadius = 10.0
        self.coordinateLabel.layer.cornerCurve = .continuous
        self.coordinateLabel.clipsToBounds = true
        self.view.addSubview(self.coordinateLabel)

        self.mapView.delegate = self
        self.updateCoordinateLabel()

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NetegramGhostStrings.locationApply, style: .done, target: self, action: #selector(self.applyTapped))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NetegramGhostStrings.locationCancel, style: .plain, target: self, action: #selector(self.cancelTapped))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let pinSize = CGSize(width: 36.0, height: 36.0)
        // Raised by half its own height so the point of the pin, not its middle, sits on the
        // centre of the map — that point is what gets read back as the coordinate.
        self.pinView.frame = CGRect(
            x: (self.view.bounds.width - pinSize.width) / 2.0,
            y: self.view.bounds.midY - pinSize.height,
            width: pinSize.width,
            height: pinSize.height
        )
        self.coordinateLabel.frame = CGRect(
            x: 16.0,
            y: self.view.bounds.height - self.view.safeAreaInsets.bottom - 60.0,
            width: self.view.bounds.width - 32.0,
            height: 44.0
        )
    }

    private func updateCoordinateLabel() {
        let center = self.mapView.centerCoordinate
        self.coordinateLabel.text = String(format: "%.5f, %.5f", center.latitude, center.longitude)
    }

    @objc private func applyTapped() {
        self.completion(self.mapView.centerCoordinate)
        self.dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        self.dismiss(animated: true)
    }
}

extension NetegramLocationPickerController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.updateCoordinateLabel()
    }
}

/// Wraps the picker in a navigation controller so it has somewhere to put its buttons.
func netegramPresentLocationPicker(window: Window1?, initial: CLLocationCoordinate2D?, completion: @escaping (CLLocationCoordinate2D) -> Void) {
    guard let window else {
        return
    }
    let picker = NetegramLocationPickerController(initial: initial, completion: completion)
    let navigation = UINavigationController(rootViewController: picker)
    window.presentNative(navigation)
}
