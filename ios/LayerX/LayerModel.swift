import Foundation
import CoreLocation
import Combine

struct LayerRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var message: String
    var creator: String
    var latitude: Double
    var longitude: Double
    var created_at: String?
    var source: String?

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
    func distance(to location: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
    }
}

struct LayerDraft {
    var title: String
    var message: String
    var creator: String
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var accuracy: CLLocationAccuracy?
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorization = manager.authorizationStatus
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0 else { return }
        coordinate = value.coordinate
        accuracy = value.horizontalAccuracy
    }
}

@MainActor
final class LayerStore: ObservableObject {
    @Published private(set) var layers: [LayerRecord] = []
    @Published var message: String = ""
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "layerx.serverURL") }
    }
    @Published var createCode: String = ""

    private let localKey = "layerx.localLayers.v1"
    private var deviceLayers: [LayerRecord] = []

    init() {
        serverURL = UserDefaults.standard.string(forKey: "layerx.serverURL") ?? ""
        if let data = UserDefaults.standard.data(forKey: localKey),
           let saved = try? JSONDecoder().decode([LayerRecord].self, from: data) {
            deviceLayers = saved
            layers = saved
        }
    }

    private func persistLocal() {
        if let data = try? JSONEncoder().encode(deviceLayers) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    var sharingEnabled: Bool {
        guard let url = URL(string: serverURL), url.scheme == "https", url.host != nil else { return false }
        return true
    }

    func nearby(_ coordinate: CLLocationCoordinate2D?) -> [LayerRecord] {
        guard let coordinate else { return layers }
        return layers.filter { $0.distance(to: coordinate) <= 1500 }
            .sorted { $0.distance(to: coordinate) < $1.distance(to: coordinate) }
    }

    func refresh(near coordinate: CLLocationCoordinate2D) async {
        guard sharingEnabled,
              let url = URL(string: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) +
                  "/api/layers?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)") else {
            layers = deviceLayers
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let result = try JSONDecoder().decode(ListResponse.self, from: data)
            var merged = Dictionary(uniqueKeysWithValues: deviceLayers.map { ($0.id, $0) })
            for item in result.layers { merged[item.id] = item }
            layers = Array(merged.values)
        } catch {
            message = "NETWORK UNAVAILABLE — USING DEVICE LAYERS"
        }
    }

    func publish(draft: LayerDraft, at location: CLLocationCoordinate2D) async -> LayerRecord? {
        let local = LayerRecord(id: UUID(), title: draft.title, message: draft.message,
                                creator: draft.creator.isEmpty ? "ANONYMOUS" : draft.creator,
                                latitude: location.latitude, longitude: location.longitude,
                                created_at: ISO8601DateFormatter().string(from: Date()), source: "local")
        if sharingEnabled && !createCode.isEmpty,
           let url = URL(string: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/layers") {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(createCode, forHTTPHeaderField: "x-layerx-create-code")
                request.httpBody = try JSONEncoder().encode(PublishPayload(title: local.title, message: local.message,
                                            creator: local.creator, latitude: local.latitude, longitude: local.longitude))
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    message = "PUBLISH FAILED. CHECK YOUR CODE AND SERVER."
                    return nil
                }
                let uploaded = try JSONDecoder().decode(CreateResponse.self, from: data).layer
                layers.insert(uploaded, at: 0)
                message = "LAYER PUBLISHED TO THE WORLD"
                return uploaded
            } catch {
                message = "PUBLISH FAILED — TRY AGAIN"
                return nil
            }
        }
        deviceLayers.insert(local, at: 0)
        layers.insert(local, at: 0)
        persistLocal()
        message = "LAYER PLACED ON THIS DEVICE"
        return local
    }

    private struct ListResponse: Decodable { let layers: [LayerRecord] }
    private struct CreateResponse: Decodable { let layer: LayerRecord }
    private struct PublishPayload: Encodable {
        let title: String
        let message: String
        let creator: String
        let latitude: Double
        let longitude: Double
    }
}
