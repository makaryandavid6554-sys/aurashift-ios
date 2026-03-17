import Foundation
import CoreLocation
import UIKit
import Combine

extension Notification.Name {
    static let deviceLocationManagerDidUpdate = Notification.Name("deviceLocationManagerDidUpdate")
}

final class DeviceLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = DeviceLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var coordinate: (latitude: Double, longitude: Double)?
    @Published private(set) var cityName: String = ""
    @Published private(set) var countryCode: String = ""
    @Published private(set) var lastErrorText: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return NSLocalizedString("Доступ к геопозиции не запрошен", comment: "location status: not requested")
        case .restricted:
            return NSLocalizedString("Доступ ограничен системой", comment: "location status: restricted")
        case .denied:
            return NSLocalizedString("Доступ запрещён", comment: "location status: denied")
        case .authorizedWhenInUse:
            return NSLocalizedString("Разрешено при использовании", comment: "location status: when in use")
        case .authorizedAlways:
            return NSLocalizedString("Разрешено всегда", comment: "location status: always")
        @unknown default:
            return NSLocalizedString("Статус неизвестен", comment: "location status: unknown")
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func refreshLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    func openSystemLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        NotificationCenter.default.post(name: .deviceLocationManagerDidUpdate, object: self)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        coordinate = (latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
        lastErrorText = nil
        reverseGeocodeIfNeeded(latest)
        NotificationCenter.default.post(name: .deviceLocationManagerDidUpdate, object: self)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorText = error.localizedDescription
    }

    // MARK: - Reverse geocoding

    private func reverseGeocodeIfNeeded(_ location: CLLocation) {
        if let last = lastGeocodedLocation, location.distance(from: last) < 500 {
            return
        }
        lastGeocodedLocation = location

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let place = placemarks?.first
            let city = [place?.locality, place?.subAdministrativeArea, place?.administrativeArea]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            let code = place?.isoCountryCode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""

            let cityChanged = !city.isEmpty && self.cityName != city
            let countryChanged = !code.isEmpty && self.countryCode != code

            if cityChanged {
                self.cityName = city
            }
            if countryChanged {
                self.countryCode = code
            }
            if cityChanged || countryChanged {
                NotificationCenter.default.post(name: .deviceLocationManagerDidUpdate, object: self)
            }
        }
    }
}
