# Bumbuild

Universal macOS build tool for Flutter projects.  
Bump version, build iOS/Android release, manage Android signing — all from a native GUI.

## Setup

1. Copy the **`Bumbuild/`** folder into the root of any Flutter project (next to `pubspec.yaml`)
2. Double-click **`Bumbuild.app`** inside the folder

That's it. No dependencies beyond Flutter itself.

## What it does

1. **Detects** your Flutter project (reads `pubspec.yaml`)
2. **Shows a dashboard** with app name, version, available platforms, signing status
3. **Platform selection** — iOS, Android, or Both
4. **Version bump** — Build number +1 or Minor version +0.1
5. **Android signing gate** — Sets up keystore signing before first Android build
6. **Builds** in a Terminal window with live, color-coded output
7. **Notifies** with sound + GUI popup when done, opens output folder

## Folder structure

```
Bumbuild/
├── Bumbuild.app/
│   └── Contents/
│       ├── MacOS/launch              ← entry point
│       ├── Resources/
│       │   ├── gui.sh                ← GUI dialogs
│       │   ├── build.sh              ← Terminal build runner
│       │   └── android_setup.sh      ← Android signing wizard
│       └── Info.plist
├── keys/                             ← keystore storage (git-ignored)
│   ├── .gitignore
│   └── README.md
└── README.md
```

## Android Signing & Keys

The `keys/` folder stores your Android signing keystores. It's auto-detected by the tool.

**First-time flow:**
1. Tool offers to **Create New** (saved to `keys/`) or **Choose Existing** (with option to copy into `keys/`)
2. Password is validated, alias auto-detected
3. `android/key.properties` and `build.gradle` are patched automatically

**When keystores exist in `keys/`:**
- The tool lists them and lets you pick one directly — no file browsing needed
- You can still create new keys or browse for other files

**Portability:** Copy the entire `Bumbuild/` folder (including `keys/`) to a new project. Your keystores come along, ready to use.

> ⚠️ The `keys/` folder is git-ignored. Never commit keystores to version control. Keep a secure backup.

## Requirements

- macOS 10.15+
- Flutter SDK installed and in PATH
- Xcode (for iOS builds)
- Java JDK (for Android keystore creation)
