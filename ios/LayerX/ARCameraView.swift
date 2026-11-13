import SwiftUI
import ARKit
import SceneKit
import UIKit
import simd

/// Real ARKit surface anchoring. Unlike the web camera preview, these cards are
/// attached to ARAnchors in a tracked 3D coordinate system.
struct ARCameraView: UIViewRepresentable {
    @ObservedObject var spatial: SpatialStore
    var draft: LayerDraft?
    var saveToken: Int
    var resetToken: Int
    var onPlaced: (SpatialLayer) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(spatial: spatial, onPlaced: onPlaced)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = true
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        context.coordinator.sceneView = view
        context.coordinator.draft = draft
        context.coordinator.lastSaveToken = saveToken
        context.coordinator.lastResetToken = resetToken
        context.coordinator.updateIndex(spatial.layers)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.place(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.startSession(restore: true)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.draft = draft
        coordinator.onPlaced = onPlaced
        coordinator.updateIndex(spatial.layers)

        if resetToken != coordinator.lastResetToken {
            coordinator.lastResetToken = resetToken
            coordinator.startSession(restore: false)
        }
        if saveToken != coordinator.lastSaveToken {
            coordinator.lastSaveToken = saveToken
            coordinator.saveMap()
        }
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        weak var sceneView: ARSCNView?
        let spatial: SpatialStore
        var draft: LayerDraft?
        var onPlaced: (SpatialLayer) -> Void
        var lastSaveToken = 0
        var lastResetToken = 0
        private let indexLock = NSLock()
        private var layerIndex: [String: SpatialLayer] = [:]
        private var lastMappingAvailable: Bool?

        init(spatial: SpatialStore, onPlaced: @escaping (SpatialLayer) -> Void) {
            self.spatial = spatial
            self.onPlaced = onPlaced
        }

        func updateIndex(_ layers: [SpatialLayer]) {
            indexLock.lock()
            layerIndex = Dictionary(uniqueKeysWithValues: layers.map { ($0.anchorName, $0) })
            indexLock.unlock()
        }

        private func layer(for name: String?) -> SpatialLayer? {
            guard let name else { return nil }
            indexLock.lock()
            defer { indexLock.unlock() }
            return layerIndex[name]
        }

        func startSession(restore: Bool) {
            guard let view = sceneView, ARWorldTrackingConfiguration.isSupported else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic
            if restore, let worldMap = spatial.loadMap() {
                configuration.initialWorldMap = worldMap
                spatial.trackingMessage = "LOOK AROUND TO REOPEN THIS SPACE"
            } else {
                spatial.trackingMessage = "MOVE SLOWLY TO SCAN SURFACES"
            }
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        @objc func place(_ recognizer: UITapGestureRecognizer) {
            guard let draft else { return }
            guard let view = sceneView else { return }
            let point = recognizer.location(in: view)

            let query = view.raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .any)
                ?? view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any)

            guard let query, let hit = view.session.raycast(query).first else {
                spatial.message = "NO SURFACE FOUND. PAN SLOWLY ACROSS A WALL OR TABLE."
                return
            }

            let layer = spatial.add(draft: draft)
            updateIndex(spatial.layers)
            let anchor = ARAnchor(name: layer.anchorName, transform: hit.worldTransform)
            view.session.add(anchor: anchor)
            onPlaced(layer)
        }

        func saveMap() {
            guard let view = sceneView else { return }
            guard !spatial.layers.isEmpty else {
                spatial.message = "PLACE A LAYER BEFORE SAVING THIS SPACE."
                return
            }
            guard let frame = view.session.currentFrame,
                  frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending else {
                spatial.message = "SCAN MORE OF THIS ROOM BEFORE SAVING ITS MAP."
                return
            }
            spatial.message = "SAVING SPATIAL MAP…"
            view.session.getCurrentWorldMap { [weak self] worldMap, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let worldMap {
                        self.spatial.save(worldMap: worldMap)
                    } else {
                        self.spatial.message = "COULD NOT CAPTURE THE SPACE: " +
                            (error?.localizedDescription ?? "PLEASE SCAN MORE AND RETRY.")
                    }
                }
            }
        }

        // ARKit recreates saved ARAnchors when it successfully relocalizes
        // with the previously archived ARWorldMap.
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let layer = layer(for: anchor.name) else { return nil }
            return makeSpatialCard(layer)
        }

        private func makeSpatialCard(_ layer: SpatialLayer) -> SCNNode {
            let root = SCNNode()
            let plane = SCNPlane(width: 0.78, height: 0.38)
            plane.cornerRadius = 0.025
            let material = SCNMaterial()
            material.diffuse.contents = cardImage(layer)
            material.lightingModel = .constant
            material.isDoubleSided = true
            plane.materials = [material]
            let card = SCNNode(geometry: plane)
            card.position = SCNVector3(0, 0.22, 0)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            card.constraints = [billboard]
            root.addChildNode(card)

            let marker = SCNSphere(radius: 0.022)
            let light = SCNMaterial()
            light.diffuse.contents = UIColor.white
            light.emission.contents = UIColor.white
            marker.materials = [light]
            let markerNode = SCNNode(geometry: marker)
            root.addChildNode(markerNode)
            return root
        }

        private func cardImage(_ layer: SpatialLayer) -> UIImage {
            let size = CGSize(width: 1100, height: 540)
            return UIGraphicsImageRenderer(size: size).image { context in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
                UIColor(white: 0.045, alpha: 0.96).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 48).fill()
                UIColor(white: 0.42, alpha: 0.9).setStroke()
                let border = UIBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 45)
                border.lineWidth = 3
                border.stroke()

                let eyebrow: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .medium),
                    .foregroundColor: UIColor(white: 0.67, alpha: 1)
                ]
                let headline: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 76, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                let body: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 37),
                    .foregroundColor: UIColor(white: 0.86, alpha: 1)
                ]
                let signature: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 25, weight: .regular),
                    .foregroundColor: UIColor(white: 0.61, alpha: 1)
                ]

                ("LAYER X  /  SPATIAL MARKER" as NSString)
                    .draw(at: CGPoint(x: 58, y: 44), withAttributes: eyebrow)
                (String(layer.title.prefix(32)) as NSString)
                    .draw(in: CGRect(x: 58, y: 118, width: 984, height: 104), withAttributes: headline)
                (String(layer.message.prefix(140)) as NSString)
                    .draw(in: CGRect(x: 60, y: 248, width: 972, height: 185), withAttributes: body)
                ("LEFT BY " + layer.creator.uppercased() as NSString)
                    .draw(at: CGPoint(x: 58, y: 463), withAttributes: signature)
                _ = context
            }
        }

        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let status: String
            switch camera.trackingState {
            case .normal: status = "SURFACES TRACKED"
            case .notAvailable: status = "TRACKING UNAVAILABLE"
            case .limited(.relocalizing): status = "LOOK AROUND TO RELOCALIZE"
            case .limited(.insufficientFeatures): status = "AIM AT A TEXTURED SURFACE"
            case .limited(.excessiveMotion): status = "MOVE THE PHONE MORE SLOWLY"
            case .limited(.initializing): status = "SCANNING ENVIRONMENT"
            @unknown default: status = "SCANNING ENVIRONMENT"
            }
            DispatchQueue.main.async { [weak self] in
                self?.spatial.trackingMessage = status
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let ready = frame.worldMappingStatus == .extending || frame.worldMappingStatus == .mapped
            guard lastMappingAvailable != ready else { return }
            lastMappingAvailable = ready
            DispatchQueue.main.async { [weak self] in
                self?.spatial.mapReady = ready
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.spatial.trackingMessage = "AR ERROR — " + error.localizedDescription
            }
        }
    }
}
