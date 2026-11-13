import SwiftUI
import RealityKit
import ARKit
import UIKit
import simd

struct LayerPlacement: Identifiable {
    let id: UUID
    let title: String
    let transform: simd_float4x4
}

struct ARCameraView: UIViewRepresentable {
    var placement: LayerPlacement?
    var discovery: LayerRecord?
    var didTapSurface: (simd_float4x4) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(didTapSurface: didTapSurface)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        context.coordinator.view = view
        if ARWorldTrackingConfiguration.isSupported {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            config.environmentTexturing = .automatic
            view.session.run(config)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.didTapSurface = didTapSurface
        if let placement, context.coordinator.lastPlaced != placement.id {
            context.coordinator.lastPlaced = placement.id
            drawCard(placement.title, in: view, at: placement.transform, inFrontOfCamera: false)
        }
        if let discovery, context.coordinator.lastDiscovered != discovery.id {
            context.coordinator.lastDiscovered = discovery.id
            if let frame = view.session.currentFrame {
                drawCard(discovery.title, in: view, at: frame.camera.transform, inFrontOfCamera: true)
            }
        }
    }

    private func drawCard(_ title: String, in view: ARView, at worldTransform: simd_float4x4, inFrontOfCamera: Bool) {
        let anchor = AnchorEntity(world: worldTransform)
        let panel = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.68, 0.26, 0.012)),
            materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.9))]
        )
        panel.position = SIMD3<Float>(0, 0, inFrontOfCamera ? -1.4 : 0.025)
        let label = ModelEntity(
            mesh: .generateText(
                String(title.prefix(45)).uppercased(),
                extrusionDepth: 0.001,
                font: UIFont.monospacedSystemFont(ofSize: 0.035, weight: .medium),
                containerFrame: CGRect(x: 0, y: 0, width: 0.56, height: 0.16),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            ),
            materials: [UnlitMaterial(color: .white)]
        )
        label.position = SIMD3<Float>(-0.28, -0.07, 0.015)
        panel.addChild(label)
        anchor.addChild(panel)
        view.scene.addAnchor(anchor)
    }

    final class Coordinator: NSObject {
        weak var view: ARView?
        var didTapSurface: (simd_float4x4) -> Void
        var lastPlaced: UUID?
        var lastDiscovered: UUID?

        init(didTapSurface: @escaping (simd_float4x4) -> Void) {
            self.didTapSurface = didTapSurface
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let point = gesture.location(in: view)
            guard let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first else { return }
            didTapSurface(hit.worldTransform)
        }
    }
}
