//
//  LocationService.swift
//  WindWhisper
//
//  位置服务 - 获取用户位置和地点名称
//

import Combine
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var locationName: String = "未知位置"
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    // MARK: - Singleton

    static let shared = LocationService()

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - Location Updates

    func startUpdatingLocation() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        locationManager.requestLocation()
    }

    // MARK: - Geocoding

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                if let error = error {
                    self?.errorMessage = "获取位置名称失败: \(error.localizedDescription)"
                    self?.locationName = "户外"
                    return
                }

                if let placemark = placemarks?.first {
                    self?.locationName = self?.formatPlacemark(placemark) ?? "户外"
                }
            }
        }
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        // 添加地点名称
        if let name = placemark.name, !name.isEmpty {
            // 检查是否是具体地点（如公园、景点）
            if placemark.areasOfInterest?.contains(name) == true {
                components.append(name)
            }
        }

        // 添加区域/街道
        if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            components.append(subLocality)
        } else if let locality = placemark.locality, !locality.isEmpty {
            components.append(locality)
        }

        // 如果没有任何信息，返回默认值
        if components.isEmpty {
            return "户外"
        }

        return components.joined(separator: " · ")
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "位置获取失败: \(error.localizedDescription)"
            print("位置获取失败: \(error)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            if self.isAuthorized {
                manager.startUpdatingLocation()
            }
        }
    }
}
