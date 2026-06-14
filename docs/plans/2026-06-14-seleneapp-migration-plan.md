# SeleneApp Migration: Repo Rename + Source Move + Branding

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move `~/SeleneMarkup`'s SwiftUI iOS app into `~/SeleneApp` (renamed from `~/Lumen`), update bundle IDs and branding, add a purple-tinted dev icon, and retire the `~/SeleneMarkup` repo.

**Architecture:** `~/SeleneApp` becomes a monorepo containing both `Sources/LumenKit/` (the Swift pipeline, Phase 1 complete) and a new `Apps/SeleneApp/` iOS app target (SeleneMarkup's UI). The two are independent for now — the app still talks to Selene's Fastify server; LumenKit is linked in a later slice. The `xcodegen` + `project.yml` pattern from SeleneMarkup carries forward unchanged.

**Tech Stack:** Swift 5.9+, SwiftUI, xcodegen (`brew install xcodegen`), SPM (LumenKit), iOS 17+ deployment target, `devicectl` for iPad deploy.

**Repos touched:** `~/Lumen` (renamed to `~/SeleneApp`), `~/SeleneMarkup` (archived at the end). All git operations happen inside those repos — NOT the `~/selene` TypeScript repo.

**Prerequisites:**
- `xcodegen` installed: `brew install xcodegen`
- iPad connected via USB for final deploy verification (optional but recommended)
- `AppIcon-1024.png` exists at `~/SeleneMarkup/Sources/SeleneMarkup/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

---

### Task 1: Rename `~/Lumen` → `~/SeleneApp` and update CLAUDE.md

**Files:**
- Rename: `~/Lumen/` → `~/SeleneApp/`
- Modify: `~/SeleneApp/CLAUDE.md`
- Modify: `~/SeleneApp/README.md`

**Step 1: Rename the directory**

```bash
mv ~/Lumen ~/SeleneApp
cd ~/SeleneApp
```

Git history is preserved — `mv` on the directory doesn't affect the repo's `.git/` folder.

**Step 2: Update CLAUDE.md — replace "Lumen" with "Selene" / "SeleneApp" throughout**

Open `~/SeleneApp/CLAUDE.md` and make these targeted replacements:
- `# Lumen Project Context` → `# SeleneApp Project Context`
- `"Lumen is the **Apple-native…"` → `"SeleneApp is the **Apple-native…"`
- `~/Lumen` → `~/SeleneApp` (all occurrences)
- `Lumen Phase 1`, `Lumen Phase 2` — keep "Phase 1", "Phase 2" but drop "Lumen" prefix or say "SeleneApp Phase 1"
- The codename note: add a line — `> **Codename:** The internal Swift package is named \`LumenKit\` — a developer-only name, not user-facing.`

**Step 3: Update README.md similarly**

Replace `Lumen` display references with `Selene` or `SeleneApp`. Keep `LumenKit` as-is (it's the package name, not a brand).

**Step 4: Verify LumenKit tests still pass**

```bash
cd ~/SeleneApp
swift test 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

**Step 5: Commit**

```bash
cd ~/SeleneApp
git add -A
git commit -m "chore: rename repo Lumen → SeleneApp, update CLAUDE.md branding"
```

---

### Task 2: Scaffold `Apps/SeleneApp/` directory structure

**Files:**
- Create: `~/SeleneApp/Apps/SeleneApp/` (directory tree)

**Step 1: Create the directory tree**

```bash
cd ~/SeleneApp
mkdir -p Apps/SeleneApp/Sources/SeleneApp/App
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Models
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Services
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Views
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset
mkdir -p Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AccentColor.colorset
mkdir -p Apps/SeleneApp/Tests/SeleneAppTests
```

**Step 2: Create a placeholder AccentColor.colorset `Contents.json`**

Create `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 3: Create the top-level asset catalog `Contents.json`**

Create `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 4: Verify structure**

```bash
find ~/SeleneApp/Apps -type d | sort
```

Expected: the directory tree above printed, no errors.

**Step 5: Commit scaffold**

```bash
cd ~/SeleneApp
git add Apps/
git commit -m "chore: scaffold Apps/SeleneApp directory structure"
```

---

### Task 3: Copy SeleneMarkup Swift source files

**Files:**
- Copy from `~/SeleneMarkup/Sources/SeleneMarkup/` to `~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/`
- Copy from `~/SeleneMarkup/Tests/SeleneMarkupTests/` to `~/SeleneApp/Apps/SeleneApp/Tests/SeleneAppTests/`

**Step 1: Copy App, Models, Services, Views**

```bash
cp ~/SeleneMarkup/Sources/SeleneMarkup/App/SeleneMarkupApp.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/App/SeleneApp.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Models/AppConfig.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Models/AppConfig.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Models/NoteDetail.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Models/NoteDetail.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Models/NoteModels.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Models/NoteModels.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Models/Worksheet.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Models/Worksheet.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Services/AnnotationService.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Services/AnnotationService.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Services/HandwritingService.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Services/HandwritingService.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Services/WorksheetService.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Services/WorksheetService.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/CanvasView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/CanvasView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/ClusterListView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/ClusterListView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/ContentView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/ContentView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/GiftSurfaceView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/GiftSurfaceView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteCanvasView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/NoteCanvasView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteListView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/NoteListView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteMetaSheet.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/NoteMetaSheet.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/RelatedNotesSheet.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/RelatedNotesSheet.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/SettingsToolbarButton.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/SettingsToolbarButton.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/SettingsView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/SettingsView.swift

cp ~/SeleneMarkup/Sources/SeleneMarkup/Views/WorksheetView.swift \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Views/WorksheetView.swift
```

**Step 2: Copy test files**

```bash
cp ~/SeleneMarkup/Tests/SeleneMarkupTests/AnnotationServiceTests.swift \
   ~/SeleneApp/Apps/SeleneApp/Tests/SeleneAppTests/AnnotationServiceTests.swift

cp ~/SeleneMarkup/Tests/SeleneMarkupTests/NoteDetailTests.swift \
   ~/SeleneApp/Apps/SeleneApp/Tests/SeleneAppTests/NoteDetailTests.swift

cp ~/SeleneMarkup/Tests/SeleneMarkupTests/SettingsViewModelTests.swift \
   ~/SeleneApp/Apps/SeleneApp/Tests/SeleneAppTests/SettingsViewModelTests.swift

cp ~/SeleneMarkup/Tests/SeleneMarkupTests/WorksheetServiceTests.swift \
   ~/SeleneApp/Apps/SeleneApp/Tests/SeleneAppTests/WorksheetServiceTests.swift
```

**Step 3: Rename the `@main` entry point**

In `Apps/SeleneApp/Sources/SeleneApp/App/SeleneApp.swift`, the struct is named `SeleneMarkupApp`. Rename it to `SeleneApp` so it matches the new product name:

Find: `struct SeleneMarkupApp: App {`
Replace: `struct SeleneApp: App {`

**Step 4: Copy the production app icon**

```bash
cp ~/SeleneMarkup/Sources/SeleneMarkup/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
   ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

**Step 5: Create the prod icon `Contents.json`**

Create `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 6: Verify all files copied**

```bash
find ~/SeleneApp/Apps/SeleneApp -name "*.swift" | wc -l
```

Expected: `24` (20 source + 4 test files)

**Step 7: Commit**

```bash
cd ~/SeleneApp
git add Apps/SeleneApp/Sources/ Apps/SeleneApp/Tests/
git commit -m "feat: import SeleneMarkup source into Apps/SeleneApp"
```

---

### Task 4: Create the purple dev icon

**Files:**
- Create: `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset/AppIconDev-1024.png`
- Create: `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset/Contents.json`

**Step 1: Generate a purple-tinted icon**

This uses macOS's built-in `sips` + an inline Python snippet (Python 3 is pre-installed on macOS). No external tools required:

```bash
ICON_SRC="$HOME/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ICON_DEV="$HOME/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset/AppIconDev-1024.png"

python3 - "$ICON_SRC" "$ICON_DEV" <<'PYEOF'
import sys, struct, zlib

# If PIL/Pillow is available, use it; otherwise fall back to a simpler tint
try:
    from PIL import Image, ImageEnhance
    img = Image.open(sys.argv[1]).convert("RGBA")
    r, g, b, a = img.split()
    # Boost red + blue channels (purple = high R + high B, low G)
    from PIL import ImageOps
    r = ImageEnhance.Brightness(r).enhance(1.2)
    g = ImageEnhance.Brightness(g).enhance(0.6)
    b = ImageEnhance.Brightness(b).enhance(1.3)
    result = Image.merge("RGBA", (r, g, b, a))
    result.save(sys.argv[2])
    print("Tinted with Pillow →", sys.argv[2])
except ImportError:
    # Pillow not installed: copy and add a note to tint manually
    import shutil
    shutil.copy(sys.argv[1], sys.argv[2])
    print("⚠️  Pillow not installed — copied icon unchanged.")
    print("    Open", sys.argv[2], "in Preview → Tools → Adjust Color")
    print("    Drag Hue slider toward purple, then File → Export As PNG.")
PYEOF
```

If Pillow is not installed (the fallback message appears), tint the icon manually in Preview or Figma — then run `swift test` in the next task and come back to verify the icon looks right on a real device.

**Step 2: Create `AppIconDev.appiconset/Contents.json`**

Create `Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "AppIconDev-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 3: Verify both icon sets exist**

```bash
ls ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIcon.appiconset/
ls ~/SeleneApp/Apps/SeleneApp/Sources/SeleneApp/Resources/Assets.xcassets/AppIconDev.appiconset/
```

Expected: each directory contains a `.png` and a `Contents.json`.

**Step 4: Commit**

```bash
cd ~/SeleneApp
git add Apps/SeleneApp/Sources/SeleneApp/Resources/
git commit -m "feat: add prod + purple dev app icons for SeleneApp"
```

---

### Task 5: Write `project.yml` for SeleneApp

**Files:**
- Create: `~/SeleneApp/Apps/SeleneApp/project.yml`

This defines two app targets (`Selene` prod + `SeleneDev` dev) with updated bundle IDs, the `SELENE_DEV` compilation flag on the dev target, and the correct icon asset names.

**Step 1: Create `Apps/SeleneApp/project.yml`**

```yaml
name: SeleneApp
options:
  bundleIdPrefix: com.selene
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true

targets:
  Selene:
    type: application
    platform: iOS
    sources:
      - path: Sources/SeleneApp
    info:
      path: Selene-Info.plist
      properties:
        CFBundleDisplayName: Selene
        UILaunchScreen: {}
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.selene.app
        PRODUCT_NAME: Selene
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: XZJ6358HHF
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "2"
        ENABLE_PREVIEWS: "YES"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon

  SeleneDev:
    type: application
    platform: iOS
    sources:
      - path: Sources/SeleneApp
    info:
      path: SeleneDev-Info.plist
      properties:
        CFBundleDisplayName: Selene Dev
        UILaunchScreen: {}
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.selene.app.dev
        PRODUCT_NAME: SeleneDev
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: SELENE_DEV
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: XZJ6358HHF
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "2"
        ENABLE_PREVIEWS: "YES"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIconDev

  SeleneAppTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests/SeleneAppTests
    dependencies:
      - target: Selene
    settings:
      base:
        DEVELOPMENT_TEAM: XZJ6358HHF
        SWIFT_VERSION: "5.9"
        IPHONEOS_DEPLOYMENT_TARGET: "17.0"
        GENERATE_INFOPLIST_FILE: "YES"

schemes:
  Selene:
    build:
      targets:
        Selene: all
        SeleneAppTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - SeleneAppTests
    archive:
      config: Release

  SeleneDev:
    build:
      targets:
        SeleneDev: all
    run:
      config: Debug
    archive:
      config: Debug
```

**Step 2: Commit**

```bash
cd ~/SeleneApp
git add Apps/SeleneApp/project.yml
git commit -m "feat: add xcodegen project.yml for SeleneApp (Selene + SeleneDev targets)"
```

---

### Task 6: Write `redeploy.sh` for SeleneApp

**Files:**
- Create: `~/SeleneApp/Apps/SeleneApp/redeploy.sh`

This is the SeleneMarkup `redeploy.sh` with scheme names updated from `SeleneMarkup`/`SeleneMarkup-Dev` to `Selene`/`SeleneDev`.

**Step 1: Copy and update redeploy.sh**

```bash
cp ~/SeleneMarkup/redeploy.sh ~/SeleneApp/Apps/SeleneApp/redeploy.sh
```

Open `~/SeleneApp/Apps/SeleneApp/redeploy.sh` and make these replacements:

- `SCHEME="SeleneMarkup"` → `SCHEME="Selene"`
- `--prod) SCHEME="SeleneMarkup"` → `--prod) SCHEME="Selene"`
- `--dev)  SCHEME="SeleneMarkup-Dev"` → `--dev)  SCHEME="SeleneDev"`
- Any reference to `SeleneMarkup.xcodeproj` → `SeleneApp.xcodeproj`

**Step 2: Make it executable**

```bash
chmod +x ~/SeleneApp/Apps/SeleneApp/redeploy.sh
```

**Step 3: Commit**

```bash
cd ~/SeleneApp
git add Apps/SeleneApp/redeploy.sh
git commit -m "feat: add redeploy.sh for SeleneApp (Selene + SeleneDev schemes)"
```

---

### Task 7: Generate Xcode project and verify both schemes build

**Files:** (no file changes — this is verification)

**Step 1: Generate the Xcode project**

```bash
cd ~/SeleneApp/Apps/SeleneApp
xcodegen generate
```

Expected: `✔ Generated project at SeleneApp.xcodeproj`

If xcodegen fails with a YAML error, read the error message — it will point to the exact line in `project.yml`.

**Step 2: Build the prod scheme against an iOS Simulator**

```bash
cd ~/SeleneApp/Apps/SeleneApp
xcodebuild \
  -scheme Selene \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=latest' \
  build \
  2>&1 | grep -E "^(Build|error:|warning: |SUCCEEDED|FAILED)" | tail -20
```

Expected last line: `** BUILD SUCCEEDED **`

**Step 3: Build the dev scheme**

```bash
cd ~/SeleneApp/Apps/SeleneApp
xcodebuild \
  -scheme SeleneDev \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=latest' \
  build \
  2>&1 | grep -E "^(Build|error:|warning: |SUCCEEDED|FAILED)" | tail -20
```

Expected last line: `** BUILD SUCCEEDED **`

**Step 4: If errors appear — common fixes**

- `Cannot find type 'SeleneMarkupApp'` — you haven't renamed the struct in `SeleneApp.swift` yet (Task 3 Step 3). Fix: rename `SeleneMarkupApp` → `SeleneApp` in that file.
- `No such module 'SeleneMarkup'` — there are no module imports to fix (it's an app target, not a framework). Check if a file accidentally has `@testable import SeleneMarkup` and update to `@testable import Selene`.
- `Missing icon set` — verify `AppIcon.appiconset/Contents.json` and `AppIconDev.appiconset/Contents.json` both exist and name real PNG files.

**Step 5: Commit**

```bash
cd ~/SeleneApp
git add Apps/SeleneApp/SeleneApp.xcodeproj/
git commit -m "chore: add generated SeleneApp.xcodeproj (xcodegen)"
```

---

### Task 8: Optional — deploy to iPad and verify side-by-side install

**Files:** (no file changes — this is deploy verification)

Skip if no iPad is connected. This verifies the two apps install independently with distinct icons.

**Step 1: Deploy prod app**

```bash
cd ~/SeleneApp/Apps/SeleneApp
./redeploy.sh --prod
```

Expected: installs "Selene" with the standard icon.

**Step 2: Deploy dev app**

```bash
cd ~/SeleneApp/Apps/SeleneApp
./redeploy.sh --dev
```

Expected: installs "Selene Dev" with the purple-tinted icon, visible alongside "Selene" on the home screen.

**Step 3: Verify the dev app connects to :5679**

Open "Selene Dev" → Settings → confirm the server URL shows `:5679`. (The `SELENE_DEV` compilation flag in `AppConfig.swift` gates this.)

---

### Task 9: Archive `~/SeleneMarkup`

**Files:**
- Create: `~/SeleneMarkup/ARCHIVED.md`

**Step 1: Write an archive notice**

Create `~/SeleneMarkup/ARCHIVED.md`:

```markdown
# Archived

This repo has been absorbed into `~/SeleneApp` (formerly `~/Lumen`).

All source files now live at `~/SeleneApp/Apps/SeleneApp/`.
The deploy script is at `~/SeleneApp/Apps/SeleneApp/redeploy.sh`.

Git history is preserved in the SeleneApp repo.
```

**Step 2: Commit the archive notice to SeleneMarkup**

```bash
cd ~/SeleneMarkup
git add ARCHIVED.md
git commit -m "chore: archive — source moved to ~/SeleneApp"
```

**Step 3: Archive the GitHub repo (if applicable)**

If `~/SeleneMarkup` has a GitHub remote, go to Settings → "Archive this repository" on GitHub. This makes the repo read-only and signals it's no longer active.

**Step 4: Final commit in SeleneApp referencing the completed migration**

```bash
cd ~/SeleneApp
git commit --allow-empty -m "chore: SeleneMarkup migration complete — ~/SeleneMarkup archived"
```

---

## Summary

After these 9 tasks:

| Before | After |
|---|---|
| `~/Lumen` | `~/SeleneApp` |
| `~/SeleneMarkup` | Archived, source in `~/SeleneApp/Apps/SeleneApp/` |
| Bundle ID: `com.chaseeasterling.selenemarkup` | `com.selene.app` |
| Bundle ID: `com.chaseeasterling.selenemarkup.dev` | `com.selene.app.dev` |
| Dev icon: same as prod | Dev icon: purple tint |
| Schemes: `SeleneMarkup` / `SeleneMarkup-Dev` | Schemes: `Selene` / `SeleneDev` |

**Next slice:** Tier 1 App Intents (`OpenWorksheetIntent`, `OpenWantsIntent`, `OpenClusterIntent`) — add to `Apps/SeleneApp/` as a new source group, register via `AppShortcutsProvider`. See `docs/plans/2026-06-14-seleneapp-ios27-siri-design.md`.
