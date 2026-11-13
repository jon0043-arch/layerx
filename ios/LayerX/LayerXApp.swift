import SwiftUI
import ARKit
import CoreLocation

@main
struct LayerXApp: App {
    var body: some Scene {
        WindowGroup {
            LayerXHome()
                .preferredColorScheme(.dark)
        }
    }
}

struct LayerXHome: View {
    @StateObject private var location = LocationService()
    @StateObject private var store = LayerStore()
    @State private var panel: Panel?
    @State private var draft: LayerDraft?
    @State private var placement: LayerPlacement?
    @State private var revealed: LayerRecord?
    @State private var lastRefresh = Date.distantPast
    @State private var title = ""
    @State private var bodyText = ""
    @State private var signature = ""

    enum Panel: String, Identifiable {
        case create, discover, settings
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARCameraView(placement: placement, discovery: revealed, didTapSurface: handleTap)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("ARKit requires a compatible iPhone.").foregroundStyle(.white)
            }

            LinearGradient(colors: [.black.opacity(0.72), .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer()
                if draft != nil {
                    Text("TAP A REAL SURFACE TO PLACE YOUR LAYER")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .padding(16)
                        .background(.black.opacity(0.8))
                        .overlay(Rectangle().stroke(.white.opacity(0.6)))
                        .padding(.horizontal, 28)
                } else if let item = revealed {
                    VStack(spacing: 8) {
                        Text("LAYER DETECTED / APPROXIMATE GPS AREA")
                            .font(.system(size: 10, design: .monospaced)).tracking(1.5)
                        Text(item.title.uppercased())
                            .font(.system(size: 26, weight: .light))
                        Text(item.message).font(.system(size: 14)).multilineTextAlignment(.center)
                        Button("CLOSE DISCOVERY ×") { revealed = nil }
                            .font(.system(size: 10, design: .monospaced)).padding(.top, 12)
                    }
                    .padding(23).frame(maxWidth: .infinity)
                    .background(.black.opacity(0.82))
                    .overlay(Rectangle().stroke(.white.opacity(0.5)))
                    .padding(.horizontal, 22)
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "scope").font(.system(size: 38, weight: .ultraLight))
                        Text("THE WORLD HAS ANOTHER LAYER.")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(1.6)
                        Text("POINT. PLACE. LEAVE. DISCOVER.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
                bottomBar
            }
        }
        .task { location.request() }
        .onReceive(location.$coordinate) { newValue in
            guard let coordinate = newValue, Date().timeIntervalSince(lastRefresh) > 25 else { return }
            lastRefresh = Date()
            Task { await store.refresh(near: coordinate) }
        }
        .sheet(item: $panel) { selected in
            switch selected {
            case .create: createSheet
            case .discover: discoverSheet
            case .settings: settingsSheet
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LAYER X").font(.system(size: 21, weight: .medium)).tracking(6)
                Spacer()
                Text("FIELD TEST / 001").font(.system(size: 9, design: .monospaced)).tracking(1.4)
            }
            HStack {
                Circle().fill(location.coordinate == nil ? Color.gray : Color.green)
                    .frame(width: 6, height: 6)
                Text(location.coordinate == nil ? "ACQUIRING LOCATION" :
                        "POSITION ACQUIRED  ±\(Int(location.accuracy ?? 0))M")
                    .font(.system(size: 9, design: .monospaced)).tracking(1)
                Spacer()
                Text("\(store.nearby(location.coordinate).count) SIGNALS")
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.8))
            if !store.message.isEmpty {
                Text(store.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(23)
    }

    private var bottomBar: some View {
        HStack(spacing: 9) {
            Button { panel = .discover } label: { iconButton("square.stack", "DISCOVER") }
            Button { panel = .create } label: {
                VStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                    Text("DROP").font(.system(size: 9, design: .monospaced)).tracking(1)
                }
                .frame(maxWidth: .infinity).frame(height: 75)
                .background(Color.white).foregroundStyle(.black)
            }
            Button { panel = .settings } label: { iconButton("slider.horizontal.3", "SETTINGS") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func iconButton(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 19, weight: .light))
            Text(text).font(.system(size: 9, design: .monospaced)).tracking(1)
        }
        .frame(maxWidth: .infinity).frame(height: 75)
        .background(.black.opacity(0.8))
        .overlay(Rectangle().stroke(.white.opacity(0.35)))
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("CONTENT") {
                    TextField("Layer title", text: $title).textInputAutocapitalization(.characters)
                    TextField("Leave a note, story, or secret", text: $bodyText, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Signature (optional)", text: $signature)
                }
                Section {
                    Text("After continuing, point your camera at a wall, floor or table and tap to place. Layers are also geo-tagged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("POINT & PLACE ↗") {
                    draft = LayerDraft(title: String(title.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines),
                                       message: String(bodyText.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines),
                                       creator: String(signature.prefix(32)).trimmingCharacters(in: .whitespacesAndNewlines))
                    panel = nil
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).count < 2 ||
                          bodyText.trimmingCharacters(in: .whitespaces).count < 2 ||
                          location.coordinate == nil)
            }
            .navigationTitle("DROP A LAYER")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("CLOSE") { panel = nil } } }
        }
    }

    private var discoverSheet: some View {
        NavigationStack {
            List {
                if store.nearby(location.coordinate).isEmpty {
                    ContentUnavailableView("NO SIGNALS HERE", systemImage: "scope",
                                           description: Text("Be the first person to leave something in this place."))
                }
                ForEach(store.nearby(location.coordinate)) { layer in
                    Button {
                        revealed = layer
                        panel = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(layer.title).font(.headline)
                            Text(layer.message).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text("BY \(layer.creator) · \(layer.source == "local" ? "THIS DEVICE" : "NEARBY")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("DISCOVER")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("CLOSE") { panel = nil } } }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("SHARED NETWORK") {
                    TextField("https://your-layerx-deployment.vercel.app", text: $store.serverURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Field-test publishing code", text: $store.createCode)
                    Text("Leave the server blank to try local-only layers. Configure the API and database to publish layers that other people can discover.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("LOCATION") {
                    if let c = location.coordinate {
                        Text("\(c.latitude), \(c.longitude)")
                    } else {
                        Button("ENABLE LOCATION") { location.request() }
                    }
                }
                Button("REFRESH NEARBY LAYERS") {
                    guard let c = location.coordinate else { return }
                    Task { await store.refresh(near: c) }
                }
            }
            .navigationTitle("SETTINGS")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("DONE") { panel = nil } } }
        }
    }

    private func handleTap(_ transform: simd_float4x4) {
        guard let draft, let coordinate = location.coordinate else { return }
        Task {
            if let layer = await store.publish(draft: draft, at: coordinate) {
                placement = LayerPlacement(id: layer.id, title: layer.title, transform: transform)
                self.draft = nil
                title = ""; bodyText = ""; signature = ""
            }
        }
    }
}
