# LAYER X
**THE WORLD HAS ANOTHER LAYER. YOU JUST FOUND IT.**

Layer X is a location-based augmented-reality platform for leaving digital content in physical places, then discovering it with another device. This repository retains the original cinematic black-and-white landing page and now contains an actual field-test product.

## What's included

| Component | Path | Works now |
|---|---|---|
| Original landing page | \`/\` | Existing marketing site, with an "OPEN THE WORLD" entry point |
| Mobile browser field test | \`/world\` | Camera preview, GPS nearby discovery, drop text, local save, bookmarks, share links |
| Shared layer REST API | \`/api/layers\` | Nearby reads + code-gated writes once Supabase variables are configured |
| Supabase database | \`database/schema.sql\` | Geo-tagged text Layer storage with RLS locked down |
| Native ARKit iPhone project | \`ios/\` | Surface detection, tap-to-place 3D text, GPS discovery and persistence client |

## Important truth about anchoring

- The **web camera** provides a camera-feed overlay and GPS discovery. It **does not** physically attach graphics to surfaces in 3D; this preview is clearly labeled.
- The **native iPhone app** uses ARKit plane detection and raycasts to attach a 3D label to a real surface **during the current AR session**.
- A layer published from one device can be discovered by another via its GPS coordinates, but is re-shown approximately in the second user's view. **Precise relocalization to the exact brick, wall, or object across separate phones is not solved yet.**
- Precise persistent cross-device attachments require a separate localization system (e.g. supported ARGeoAnchors, visual positioning, or cloud anchors) and on-device testing.

## Run the browser app

Prerequisites: Node.js 20+.

\`\`\`bash
npm install
npm run dev
\`\`\`

Visit \`http://localhost:3000/world\`. Camera APIs require HTTPS on a remote device; browsers allow localhost for development. Grant location and camera access. Without a configured Supabase project, Layers save to the browser's local storage **only on that device**.

## Enable shared layers

1. Create a Supabase project.
2. Execute \`database/schema.sql\` in its SQL editor. It enables RLS and grants **no public table access**.
3. Add \`SUPABASE_URL\`, \`SUPABASE_SERVICE_ROLE_KEY\`, and \`LAYERX_CREATE_ACCESS_CODE\` as **server-side** environment variables in Vercel. Keep the service role key secret; **never prefix it with NEXT_PUBLIC_**.
4. Deploy the Next.js site with HTTPS. Reload \`/world\`, allow location, and enter the creation code when dropping a Layer. With the code, it is published and can appear on other devices within approximately 1.5km.
5. Public discovery GET requests are read through the server API. Only someone with the field-test code may publish to the shared table.

This access-code gate is for controlled testing, **not public launch**. Before public use, build accounts, reporting, moderation, deletion, per-user and IP rate limits, abuse prevention, and consent/privacy controls for sensitive physical locations.

## Run the native ARKit iPhone app

Requirements: a Mac with Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and a compatible physical iPhone. ARKit world tracking does not run in the iOS Simulator.

\`\`\`bash
cd ios
xcodegen generate
open LayerX.xcodeproj
\`\`\`

Select your developer signing team in Xcode and run on your iPhone. Grant camera and location permissions.

The native app initially operates in local-only mode. In its **SETTINGS**, enter your HTTPS web deployment origin (e.g. \`https://your-project.vercel.app\`) and the publishing code if you want shared layers. A server URL alone enables discovery; creating a shared layer requires the code. Publishing code is held in memory during the app session, not written to device defaults.

Flow: **DROP → write a title/message → POINT camera → TAP detected surface → leave a Layer → DISCOVER nearby**.

## MVP boundaries

Version 0.1 supports text Layers and user-provided signatures. It does **not** yet support production authentication, photo/video/3D uploads, comments, likes, profiles, precise visual localization, permanent AR world maps, or a public App Store distribution.

The code has been committed to GitHub but must still be compiled and tested on a real iPhone. This environment cannot run Xcode or verify ARKit tracking on hardware.
