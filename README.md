# Mandroid Finder

Surfaces connected Android devices inside macOS Finder's **Locations** sidebar — the same way iCloud Drive and Google Drive appear — using Apple's File Provider framework. Browsing, drag-and-drop, Quick Look, and Spotlight all work against the device over the adb wire protocol without launching a custom app UI.

Sibling project to `mandroid_transfer`, which keeps the standalone window-based file manager experience.

## How it works

```
MandroidFinder.app (host)
  ├─ Polls the adb server at 127.0.0.1:5037 for connected devices
  ├─ For each connected device, calls NSFileProviderManager.add(domain)
  ├─ For each disconnected device, calls NSFileProviderManager.remove(domain)
  └─ Embeds:
       MandroidFileProvider.appex   ← NSFileProviderReplicatedExtension
                                      Speaks the adb wire protocol directly:
                                        host:devices-l, host:transport:<serial>,
                                        shell:ls -la /sdcard/, sync:RECV, sync:SEND
```

Each device gets its own sidebar entry under Finder → Locations, named after the device model.

**No `adb` binary is bundled.** The extension speaks adb's TCP protocol natively — it just needs an adb server running locally (Android Studio, `brew install --cask android-platform-tools`, etc.).

## Requirements

- macOS 14+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Apple Developer account (free Apple ID works for local testing; Developer ID required for distribution)
- An adb server running locally — `adb start-server` from any installed `platform-tools` is enough; the project does not embed one.

## First-time setup

1. Clone the repo.
2. Create your local config:
   ```bash
   cp Configs/Local.xcconfig.example Configs/Local.xcconfig
   ```
   Edit `Configs/Local.xcconfig` and set:
   - `DEVELOPMENT_TEAM` — your Apple Developer Team ID (find at developer.apple.com/account → Membership)
   - `BUNDLE_ID_PREFIX` — a reverse-domain prefix you control (e.g. `com.yourname.mandroidfinder`)

   `Local.xcconfig` is gitignored, so your personal values never get committed.

3. Build:
   ```bash
   ./Scripts/build.sh
   ```
   Runs `xcodegen generate` and builds the app.

## Run

```bash
open /Users/<you>/Library/Developer/Xcode/DerivedData/MandroidFinder-*/Build/Products/Debug/MandroidFinder.app
```

Connect an Android device with USB debugging enabled. Within ~2 seconds:
- A new entry appears under Finder → **Locations**, named after the device model.
- Click it to browse `/sdcard`.
- Drag files in/out for `sync:SEND` / `sync:RECV` over the adb protocol.

## Project layout

```
mandroid_finder/
├── project.yml                 # XcodeGen spec — single source of truth
├── Configs/
│   ├── Build.xcconfig          # Default settings (committed)
│   ├── Local.xcconfig.example
│   └── Local.xcconfig          # Your team ID + bundle prefix (gitignored)
├── Core/
│   ├── ADBService.swift        # Public API used by App and Extension
│   ├── ADBProtocol/
│   │   ├── ADBConnection.swift # NWConnection wrapper, async byte I/O
│   │   ├── ADBClient.swift     # host:* services + shell mode
│   │   └── ADBSync.swift       # sync sub-protocol (RECV / SEND / STAT)
│   ├── AppGroup.swift
│   └── Models/
│       ├── AndroidFile.swift   # ls -la output parser
│       └── DeviceInfo.swift
├── App/                        # Host app (status window + domain lifecycle)
├── Extension/                  # NSFileProviderReplicatedExtension
├── Scripts/
│   ├── build.sh                # Generate xcodeproj + build
│   └── release.sh              # Sign + notarize for distribution
└── (.xcodeproj generated; gitignored)
```

## Status

- [x] Read: enumerate directories via `shell:ls -la`, fetch file contents via `sync:RECV`
- [x] Write: create folder (`mkdir -p`), push file (`sync:SEND`), delete (`rm -rf`), rename (`mv`)
- [x] Per-device domain lifecycle keyed on stable serial
- [x] Disambiguate display name when multiple devices share a model
- [x] Both targets sandboxed; only `network.client` entitlement needed
- [x] Native adb-protocol client in pure Swift — no bundled binary
- [x] Handles non-UTF-8 filenames lossily (Shift-JIS / GBK / etc. show up rather than aborting the listing)
- [x] Event-driven device detection via `host:track-devices-l` (long-lived stream; auto-reconnect on `adb kill-server`)
- [ ] Sync anchor / change observation (currently a no-op — Finder refreshes on user navigation)
- [ ] Long-running transfer progress reporting via NSProgress

## Verification (manual, requires real device)

1. Build the app via `./Scripts/build.sh`.
2. Bundle audit:
   ```bash
   APP="$(find ~/Library/Developer/Xcode/DerivedData/MandroidFinder-*/Build/Products/Debug -name MandroidFinder.app)"
   find "$APP" -name adb   # → empty (no bundled binary)
   du -sh "$APP"           # → ~1 MB
   ```
3. Make sure an adb server is running: `adb devices` from Terminal.
4. Launch the app, confirm "ADB server: connected" in the status window.
5. Connect an Android device → entry appears under Finder → Locations.
6. Click → directory listing populates.
7. Drag a file out → triggers `sync:RECV`.
8. Drag a file in → triggers `sync:SEND`. Verify on-device with `adb shell ls`.
9. `adb kill-server` → status switches to "unreachable" within one poll cycle.

## License

MIT
