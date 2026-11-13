import SwiftUI
import ARKit
import CoreLocation

@main
struct LayerXApp: App {
    var body: some Scene {
        WindowGroup {
            LayerXHome().preferredColorScheme(.dark)
        }
    }
}

/// Native camera-first interface. Nearby GPS data is intentionally kept out of
/// the AR scene until it has real spatial localization.
struct LayerXHome: View {
    @StateObject private var spatial = SpatialStore()
    @StateObject private var location = LocationService()
    @StateObject private var nearbyStore = LayerStore()

    @State private var panel: Panel?
    @State private var draft: LayerDraft?
    @State private var saveToken = 0
    @State private var resetToken = 0
    @State private var showingResetConfirmation = false
    @State private var lastRefresh = Date.distantPast
    @State private var title = ""
    @State private var note = ""
    @State private var signature = ""

    private let ink = Color(red: 0.055, green: 0.055, blue: 0.065)

    enum Panel: String, Identifiable {
        case compose, discover, settings
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARCameraView(
                    spatial: spatial,
                    draft: draft,
                    saveToken: saveToken,
                    resetToken: resetToken,
                    onPlaced: { _ in
                        draft = nil
                        title = ""
                        note = ""
                        signature = ""
                    }
                )
                .ignoresSafeArea()
            } else {
                ink.ignoresSafeArea()
                Text("ARKit is not available on this device.")
                    .foregroundStyle(.white)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.80), location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .clear, location: 0.59),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 25)
                scenePrompt
                Spacer(minLength: 25)
                controls
            }
        }
        .statusBarHidden()
        .task { location.request() }
        .onReceive(location.$coordinate) { coordinate in
            guard let coordinate, Date().timeIntervalSince(lastRefresh) > 30 else { return }
            lastRefresh = Date()
            Task { await nearbyStore.refresh(near: coordinate) }
        }
        .sheet(item: $panel) { selected in
            switch selected {
            case .compose: composeSheet
            case .discover: discoverSheet
            case .settings: settingsSheet
            }
        }
        .alert("Start a new space?", isPresented: $showingResetConfirmation) {
            Button("Erase local anchors", role: .destructive) {
                spatial.clearSpace()
                draft = nil
                resetToken += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved spatial map and its local Layers from this iPhone.")
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Text("LAYER").fontWeight(.light).tracking(4.3)
                    Text("X").fontWeight(.bold).tracking(-0.4)
                }
                .font(.system(size: 23, design: .default))
                Spacer()
                Text("SPATIAL / 01")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2).foregroundStyle(.white.opacity(0.72))
                Button { panel = .settings } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 43, height: 43)
                        .background(.white.opacity(0.11), in: Circle())
                }
                .padding(.leading, 9)
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 9) {
                Circle()
                    .fill(spatial.mapReady ? Color.green : Color.white.opacity(0.55))
                    .frame(width: 7, height: 7)
                Text(spatial.trackingMessage.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(2)
                    .tracking(0.5)
                Spacer()
                if spatial.hasSavedMap {
                    Label("MAP SAVED", systemImage: "checkmark.circle")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 13)
    }

    @ViewBuilder
    private var scenePrompt: some View {
        if draft != nil {
            VStack(spacing: 22) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 74, weight: .ultraLight))
                    .shadow(color: .white.opacity(0.7), radius: 13)
                Text("TAP A SURFACE")
                    .font(.system(size: 25, weight: .light))
                    .tracking(1.4)
                Text("Aim at a wall, table or floor.\nTap where you want your Layer to live.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.73))
                    .lineSpacing(5)
                Button("CANCEL PLACEMENT") { draft = nil }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .padding(.top, 10)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else if spatial.layers.isEmpty {
            VStack(spacing: 11) {
                Image(systemName: "scope")
                    .font(.system(size: 49, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 6)
                Text("THE WORLD ISN'T EMPTY.")
                    .font(.system(size: 16, weight: .medium))
                    .tracking(1.7)
                Text("LEAVE SOMETHING BEHIND.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
        } else {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 39, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.48))
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        VStack(spacing: 17) {
            if !spatial.message.isEmpty {
                Text(spatial.message)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
                    .padding(.horizontal, 23)
            }

            HStack(alignment: .center, spacing: 0) {
                Button { panel = .discover } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 24, weight: .ultraLight))
                        Text("EXPLORE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Explore your Layers")

                Button { panel = .compose } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.55), lineWidth: 1.4)
                            .frame(width: 94, height: 94)
                        Circle().fill(.white)
                            .frame(width: 76, height: 76)
                        Image(systemName: "plus")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(.black)
                    }
                }
                .accessibilityLabel("Drop a new Layer")

                Button { saveToken += 1 } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 24, weight: .ultraLight))
                        Text("SAVE SPACE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Save this space and its anchors")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 15)

            HStack(spacing: 12) {
                Image(systemName: "location.north.circle")
                    .font(.system(size: 13))
                Text(spatial.layers.count == 1 ? "1 SPATIAL ANCHOR" : "\(spatial.layers.count) SPATIAL ANCHORS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                Spacer()
                Text(spatial.mapReady ? "READY TO SAVE" : "SCANNING")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .padding(.top, 21)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(ink.opacity(0.84))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.23)).frame(width: 39, height: 4).padding(.top, 9)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var composeSheet: some View {
        NavigationStack {
            ZStack {
                ink.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Text("PLACE SOMETHING\nIN THE WORLD.")
                            .font(.system(size: 39, weight: .light))
                            .tracking(-1.5)
                            .padding(.top, 32)

                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("01 / TITLE")
                            TextField("Give it a name", text: $title)
                                .font(.system(size: 19))
                                .textInputAutocapitalization(.sentences)
                                .padding(17)
                                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("02 / MESSAGE")
                            TextEditor(text: $note)
                                .font(.system(size: 17))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 160, maxHeight: 180)
                                .padding(12)
                                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("03 / SIGNATURE")
                            TextField("Anonymous", text: $signature)
                                .font(.system(size: 17))
                                .padding(17)
                                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text("Only you can see this exact spatial anchor until cross-device localization is added. No precise physical position is published.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.53))
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            draft = LayerDraft(
                                title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                                message: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280)),
                                creator: String(signature.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
                            )
                            panel = nil
                        } label: {
                            HStack {
                                Text("POINT & PLACE").tracking(1.2)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(20)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).count < 2
                                  || note.trimmingCharacters(in: .whitespaces).count < 2)
                        .opacity(title.trimmingCharacters(in: .whitespaces).count < 2
                                  || note.trimmingCharacters(in: .whitespaces).count < 2 ? 0.4 : 1)
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("NEW LAYER").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { panel = nil }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .toolbarBackground(ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.55))
    }

    private var discoverSheet: some View {
        NavigationStack {
            List {
                Section {
                    if spatial.layers.isEmpty {
                        Text("Nothing anchored yet. Drop a Layer, tap a surface, and save the space.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(spatial.layers) { layer in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(layer.title, systemImage: "scope")
                                    .font(.system(size: 18, weight: .medium))
                                Text(layer.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.73))
                                Text("ANCHORED IN YOUR SAVED SPACE · " + layer.creator.uppercased())
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                            .padding(.vertical, 12)
                        }
                    }
                } header: {
                    Text("MY REAL AR ANCHORS")
                } footer: {
                    Text("These objects are anchored to local AR world coordinates. Save the space, then revisit it to test relocalization.")
                }

                Section {
                    let nearby = nearbyStore.nearby(location.coordinate)
                    if nearby.isEmpty {
                        Text("No shared GPS-based Layers nearby.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nearby) { layer in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(layer.title).font(.headline)
                                Text(layer.message).font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("GPS AREA ONLY — NOT A PRECISE AR ANCHOR")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text("NEARBY / APPROXIMATE")
                } footer: {
                    Text("Shared location tags do not currently provide the exact visual pose needed to place another person's layer on a specific wall.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ink)
            .navigationTitle("DISCOVER")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("DONE") { panel = nil } } }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("SPATIAL MEMORY") {
                    Label(spatial.hasSavedMap ? "Saved map on this iPhone" : "No spatial map saved yet",
                          systemImage: spatial.hasSavedMap ? "checkmark.circle" : "circle.dotted")
                    Text("Saving a map lets ARKit attempt to restore these same anchors when you return to this room.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Start a new space", role: .destructive) {
                        panel = nil
                        showingResetConfirmation = true
                    }
                }
                Section("OPTIONAL SHARED GPS LAYERS") {
                    TextField("https://your-domain.vercel.app", text: $nearbyStore.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Shared GPS notes are shown only in Discover. They are not automatically rendered as physical AR anchors.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("DEVICE") {
                    Text("iPhone ARKit / iOS 17+")
                    if let coordinate = location.coordinate {
                        Text("GPS: \(coordinate.latitude), \(coordinate.longitude)")
                    } else {
                        Button("Enable location for nearby notes") { location.request() }
                    }
                }
            }
            .navigationTitle("SETTINGS")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("DONE") { panel = nil } } }
        }
    }
}
