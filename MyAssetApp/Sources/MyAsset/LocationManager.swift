import CoreLocation
import Foundation

// MARK: - 로컬 설정

enum MyAssetFiles {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MyAsset", isDirectory: true)
}

struct HomeLocation: Decodable {
    let latitude: Double
    let longitude: Double
    let name: String
    private static let threshold: Double = 400

    static var configured: HomeLocation? {
        let url = MyAssetFiles.directory.appendingPathComponent("home-location.json")
        guard let data = try? Data(contentsOf: url),
              let home = try? JSONDecoder().decode(Self.self, from: data),
              CLLocationCoordinate2DIsValid(
                  CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
              )
        else { return nil }
        return home
    }

    func distance(from location: CLLocation) -> Double {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    func contains(_ location: CLLocation) -> Bool {
        distance(from: location) <= Self.threshold
    }
}

// MARK: - location.json 저장 구조

struct LocationRecord: Codable {
    var latitude:  Double
    var longitude: Double
    var address:   String
    var updatedAt: String
    var isHome:    Bool
}

// MARK: - LocationManager

@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let clm = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var currentAddress:  String = ""
    @Published var authStatus:      CLAuthorizationStatus = .notDetermined
    @Published var isAtHome:        Bool = false
    @Published var isLoading:       Bool = false

    /// 집까지 거리 (m). nil이면 위치 미확인.
    var distanceFromHome: Double? {
        guard let currentLocation else { return nil }
        return HomeLocation.configured?.distance(from: currentLocation)
    }

    static var locationFileURL: URL {
        MyAssetFiles.directory.appendingPathComponent("location.json")
    }

    private override init() {
        super.init()
        clm.delegate = self
        clm.desiredAccuracy = kCLLocationAccuracyKilometer
        authStatus = clm.authorizationStatus
        // 앱 시작 시 이전에 저장된 위치 불러오기
        loadPersistedLocation()
    }

    func requestUpdate() {
        switch clm.authorizationStatus {
        case .notDetermined:
            clm.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break   // WeatherView에서 권한 거부 배너 표시
        default:    // .authorized / .authorizedAlways / .authorizedWhenInUse (macOS 11+)
            isLoading = true
            clm.requestLocation()
        }
    }

    // MARK: - 저장된 위치 복원

    private func loadPersistedLocation() {
        guard let data = try? Data(contentsOf: Self.locationFileURL),
              let record = try? JSONDecoder().decode(LocationRecord.self, from: data)
        else { return }

        currentAddress = record.address
        let location = CLLocation(latitude: record.latitude, longitude: record.longitude)
        currentLocation = location
        isAtHome = HomeLocation.configured?.contains(location) ?? false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let home = HomeLocation.configured
        let homeName = home?.contains(loc) == true ? home?.name : nil

        Task { @MainActor in
            self.currentLocation = loc
            self.isAtHome = homeName != nil
            self.isLoading = false
            self.geocodeAndPersist(loc, homeName: homeName)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.isLoading = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authStatus = status
            let granted = (status != .notDetermined && status != .denied && status != .restricted)
            if granted {
                self.isLoading = true
                manager.requestLocation()
            }
        }
    }

    // MARK: 역지오코딩 + 저장

    @MainActor
    private func geocodeAndPersist(_ location: CLLocation, homeName: String?) {
        if let homeName {
            currentAddress = homeName
            persist(location, address: homeName, atHome: true)
            return
        }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] marks, _ in
            guard let self, let mark = marks?.first else { return }
            Task { @MainActor in
                let parts = [mark.administrativeArea,
                             mark.locality,
                             mark.subLocality].compactMap { $0 }
                let addr = parts.isEmpty ? "알 수 없는 위치" : parts.joined(separator: " ")
                self.currentAddress = addr
                self.persist(location, address: addr, atHome: false)
            }
        }
    }

    private func persist(_ location: CLLocation, address: String, atHome: Bool) {
        let record = LocationRecord(
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            address:   address,
            updatedAt: ISO8601DateFormatter().string(from: .now),
            isHome:    atHome
        )
        if let data = try? JSONEncoder().encode(record) {
            try? FileManager.default.createDirectory(
                at: MyAssetFiles.directory, withIntermediateDirectories: true
            )
            try? data.write(to: Self.locationFileURL, options: .atomic)
        }
    }
}
