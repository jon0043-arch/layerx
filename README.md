# LAYER X

**The world has another layer.**

Layer X has two intentionally different experiences:

- **Native iPhone AR (real spatial anchors)** — The iOS app uses ARKit plane detection, a tap raycast, and named ARAnchors to keep digital cards attached to physical 3D positions as you move. It can save an ARWorldMap to the device and attempt to restore those anchors on a later visit.
- **Browser companion (/world)** — A redesigned GPS discovery and text-note experience. It is **not augmented reality** and does not show objects attached to a wall or surface.

## What works in the native prototype

1. Camera-first, minimal interface, and dedicated Drop/Explore/Save Space controls.
2. Write a title, message, and signature.
3. Scan a wall, table, or floor, then tap the real surface to attach a 3D card using an ARAnchor.
4. Walk around and see the anchored object remain in the physical location while ARKit tracking is successful.
5. When the mapping status is ready, press **SAVE SPACE** to archive an ARWorldMap containing the anchors.
6. Close and reopen the app in the **same room**, look around the previously scanned area, and allow ARKit to relocalize. The anchored cards can reappear at their original coordinates if relocalization succeeds.
7. Start a new space from Settings if ARKit gets stuck trying to relocalize to an old place.

**Limitations:** Spatial persistence is on the same iPhone and only within a successfully relocalized saved environment. Precise cross-device wall/object attachments, user accounts, public content moderation, and an App Store build are **not implemented**. The native app is not remotely installable from a website.

## Build and install on your iPhone

You need a Mac with Xcode installed, a physical iPhone that supports ARKit, and XcodeGen (the project is generated from `ios/project.yml`). You can sign the app with a personal development team for your own device.

```bash
git clone https://github.com/jon0043-arch/layerx.git
cd layerx/ios
brew install xcodegen
xcodegen generate
open LayerX.xcodeproj
```

In Xcode select the **LayerX** target → **Signing & Capabilities**, choose your Apple development team, and if necessary change the bundle identifier to a unique value. Connect your iPhone, trust the computer and enable Developer Mode if prompted. Select the iPhone as the run destination and press **Run** (▶). Grant camera/location permissions when asked.

### Five-minute physical anchor test

1. Point your phone at a well-lit, textured wall or tabletop and move slowly while ARKit maps it.
2. Press the center **+** button, enter a title and a note, then choose **POINT & PLACE**.
3. Tap the real surface. The AR card should stay attached to that real position when you walk around it.
4. Continue scanning the room until the bottom status says **READY TO SAVE**. Press **SAVE SPACE** and look for a success message.
5. Close and reopen the app in the same room. Move around the same surfaces until tracking relocalizes. If it succeeds, your card should return in the same physical place.

Real AR tracking and successful relocalization **must be verified on-device**. Code compilation alone cannot prove spatial stability.

## Build checks

- GitHub Actions `.github/workflows/ios-build.yml` compiles the native app with Xcode on a macOS runner.
- `.github/workflows/build.yml` verifies the Next.js website.
- App code: `ios/LayerX/LayerXApp.swift`, `ARCameraView.swift`, `SpatialStore.swift`, and `LayerModel.swift`.

## Browser companion

```bash
npm install
npm run dev
```

Open `http://localhost:3000/world`. The companion shows local GPS Layers, lets you create device-local notes, and has a nearby radar. It intentionally does **not** show a fake camera-based AR overlay. The live deployment, when configured, uses HTTPS.

## Optional shared GPS notes

The `app/api/layers/route.js` API can connect to Supabase for controlled geo-tagged text notes. Run `database/schema.sql` in your Supabase SQL editor and configure these **server-only** environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `LAYERX_CREATE_ACCESS_CODE`

Never put the service role key in public frontend code. The access code is for private field testing only, not launch-grade authentication. Before inviting public users, add authentication, moderation, reporting, removal, rate limiting, and location privacy controls.

Shared notes are **approximate GPS content**, not cross-device spatial anchors.

## Engineering roadmap

- Native 3D interactions, anchored media and audio.
- A place/space selection flow for multiple environments; current version stores a single active local world map.
- Reliable, privacy-aware cross-device localization: shared world maps, supported geo anchors, or visual-positioning methods as appropriate, tested in the environments where they'll be used.
- Accounts, abuse prevention, permissions, and sharing.
- TestFlight distribution after native QA and Apple signing setup.
