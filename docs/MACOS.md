# macOS desktop build

On a Mac with Xcode Command Line Tools and Node.js 22.13 or newer:

```bash
bash scripts/build-dmg.sh
```

The script installs locked dependencies, downloads the matching official Node.js
24.22.1 runtime (with SHA-256 verification), builds Next.js standalone output,
compiles a native WebKit window, and creates `dist/PerkRadar-0.2.0-arm64.dmg`
on Apple Silicon or `dist/PerkRadar-0.2.0-x86_64.dmg` on Intel. Internet access is
required to build. End users do not need to install Node.js.

Alternatively, push these changes to your GitHub repository and run **Actions →
Build macOS DMG → Run workflow**. Download the architecture-specific artifact
after the workflow succeeds and unzip it to obtain the DMG and checksum.

Open the DMG and drag PerkRadar to Applications. The app requires macOS 13.5 or
newer. It binds exclusively to `127.0.0.1:38471`; stop an existing service using
that port first. Database and logs live in
`~/Library/Application Support/PerkRadar/`. Favorites and claimed state remain
in the app's persistent WebKit store, separate from Safari or Chrome. External
article links open in the default browser. Closing the window quits the app and
its server; background refresh runs only while the app is open.

These builds use ad hoc signing and are **not notarized**. macOS may block a
downloaded app; for a build you trust, use System Settings → Privacy & Security →
Open Anyway. Public distribution with a verified publisher requires an Apple
Developer signing certificate and notarization, which this workflow does not
configure.

Linux cannot run this packaging script: Swift AppKit/WebKit compilation,
codesign, and hdiutil require macOS. The macOS workflow and native wrapper must
be validated on a Mac before considering the desktop build verified.
