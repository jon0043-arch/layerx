import Foundation
import ARKit
import Combine

/// Local, genuinely spatial layers. A saved ARWorldMap restores their ARAnchors
/// after ARKit successfully relocalizes in the same physical environment.
struct SpatialLayer: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let message: String
    let creator: String
    let createdAt: Date

    var anchorName: String { "layerx:" + id.uuidString }
}

@MainActor
final class SpatialStore: ObservableObject {
    @Published private(set) var layers: [SpatialLayer] = []
    @Published private(set) var hasSavedMap = false
    @Published var trackingMessage = "MOVE YOUR PHONE SLOWLY"
    @Published var message = ""
    @Published var mapReady = false

    private let indexURL: URL
    private let mapURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LayerX", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        indexURL = directory.appendingPathComponent("layers.json")
        mapURL = directory.appendingPathComponent("worldmap.archive")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([SpatialLayer].self, from: data) {
            layers = decoded
        }
        hasSavedMap = FileManager.default.fileExists(atPath: mapURL.path)
    }

    func lookup(anchorName: String?) -> SpatialLayer? {
        guard let anchorName else { return nil }
        return layers.first(where: { $0.anchorName == anchorName })
    }

    func add(draft: LayerDraft) -> SpatialLayer {
        let layer = SpatialLayer(
            id: UUID(),
            title: String(draft.title.prefix(60)),
            message: String(draft.message.prefix(280)),
            creator: String((draft.creator.isEmpty ? "ANONYMOUS" : draft.creator).prefix(32)),
            createdAt: Date()
        )
        layers.insert(layer, at: 0)
        persistIndex()
        message = "LAYER ANCHORED. SAVE THE SPACE TO KEEP IT."
        return layer
    }

    private func persistIndex() {
        do {
            let data = try JSONEncoder().encode(layers)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            message = "UNABLE TO SAVE LAYER METADATA: " + error.localizedDescription
        }
    }

    func save(worldMap: ARWorldMap) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
            try data.write(to: mapURL, options: .atomic)
            hasSavedMap = true
            message = "SPATIAL MAP SAVED. RETURN HERE TO REOPEN IT."
        } catch {
            message = "COULDN'T SAVE THIS SPACE: " + error.localizedDescription
        }
    }

    func loadMap() -> ARWorldMap? {
        guard let data = try? Data(contentsOf: mapURL) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
        } catch {
            message = "SAVED MAP COULD NOT BE OPENED."
            return nil
        }
    }

    func clearSpace() {
        try? FileManager.default.removeItem(at: mapURL)
        try? FileManager.default.removeItem(at: indexURL)
        layers.removeAll()
        mapReady = false
        hasSavedMap = false
        message = "NEW SPACE STARTED. OLD SPATIAL ANCHORS CLEARED."
    }
}
