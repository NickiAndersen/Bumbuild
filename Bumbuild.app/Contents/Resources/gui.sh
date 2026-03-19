#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║  Universal Flutter Build Tool — GUI              ║
# ╚══════════════════════════════════════════════════╝
PROJECT_DIR="$1"
RESOURCES="$2"
TOOL_DIR="$3"
cd "$PROJECT_DIR"

APP_NAME=$(grep "^name:" pubspec.yaml | sed "s/name: *//" | head -1)
VERSION=$(grep "^version:" pubspec.yaml | sed "s/version: *//")
BASE_VER=$(echo "$VERSION" | sed "s/+[0-9]*$//")
BUILD_NUM=$(echo "$VERSION" | sed "s/.*+//")

# Detect available platforms
HAS_IOS=false
HAS_ANDROID=false
[ -d "ios" ] && HAS_IOS=true
[ -d "android" ] && HAS_ANDROID=true

# Detect Android signing status
SIGNING_STATUS="Not configured"
KEYS_DIR="$TOOL_DIR/keys"
if [ -f "android/key.properties" ]; then
  S_ALIAS=$(grep "keyAlias" android/key.properties 2>/dev/null | sed 's/keyAlias=//')
  S_PATH=$(grep 'storeFile' android/key.properties 2>/dev/null | sed 's/storeFile=//')
  S_FILE=$(basename "$S_PATH" 2>/dev/null)
  if echo "$S_PATH" | grep -q "/keys/"; then
    SIGNING_STATUS="$S_ALIAS  ✓ keys/$S_FILE"
  else
    SIGNING_STATUS="$S_ALIAS ($S_FILE)"
  fi
fi

# Build platform info string
PLAT_INFO=""
$HAS_IOS && PLAT_INFO="iOS"
$HAS_ANDROID && { [ -n "$PLAT_INFO" ] && PLAT_INFO="$PLAT_INFO, Android" || PLAT_INFO="Android"; }

# ════════════════════════════════════════════════════
#  MAIN DIALOG — One smart screen
# ════════════════════════════════════════════════════

# Build button list for platforms
if $HAS_IOS && $HAS_ANDROID; then
  PLAT_BUTTONS='"iOS", "Android", "Both"'
  PLAT_DEFAULT='"iOS"'
elif $HAS_IOS; then
  PLAT_BUTTONS='"iOS"'
  PLAT_DEFAULT='"iOS"'
elif $HAS_ANDROID; then
  PLAT_BUTTONS='"Android"'
  PLAT_DEFAULT='"Android"'
else
  osascript -e 'display alert "⚠️ No Platforms" message "Neither ios/ nor android/ folder found in this project." as critical'
  exit 1
fi

RESULT=$(osascript <<EOT
  tell application "System Events"
    activate
    set appIcon to missing value
    try
      set appIcon to (POSIX file "$RESOURCES/icon.png") as alias
    end try
  end tell

  set dialogText to "┌─────────────────────────────────┐
│  📱  $APP_NAME
│  📦  Version: $VERSION
│  🖥️  Platforms: $PLAT_INFO
│  🔑  Android Signing: $SIGNING_STATUS
└─────────────────────────────────┘

Choose build platform:"

  try
    set platformChoice to button returned of (display alert "Flutter Build Tool" message dialogText buttons {$PLAT_BUTTONS} default button $PLAT_DEFAULT)
  on error
    return "CANCEL"
  end try

  -- Ask bump type
  try
    set bumpChoice to button returned of (display alert "Version Bump" message "Current: $VERSION

How to bump?" buttons {"Cancel", "Minor  ($BASE_VER → " & "$((${BASE_VER%%.*})).$(( $(echo $BASE_VER | cut -d. -f2) + 1)).0" & ")", "Build +1  (+" & "$(($BUILD_NUM + 1))" & ")"} default button 3)
  on error
    return "CANCEL"
  end try

  if bumpChoice is "Cancel" then return "CANCEL"

  return platformChoice & "|" & bumpChoice
EOT
)

if [ "$RESULT" == "CANCEL" ] || [ -z "$RESULT" ]; then exit 0; fi

# Parse result
PLATFORM=$(echo "$RESULT" | cut -d'|' -f1)
BUMP_RAW=$(echo "$RESULT" | cut -d'|' -f2)

# Normalize bump choice
if echo "$BUMP_RAW" | grep -qi "Build"; then
  BUMP="Build +1"
else
  BUMP="Minor +0.1"
fi

# Normalize platform
if [ "$PLATFORM" == "Both" ]; then PLATFORM="Begge"; fi

# ════════════════════════════════════════════════════
#  ANDROID SIGNING — Required gate
# ════════════════════════════════════════════════════
if [ "$PLATFORM" == "Android" ] || [ "$PLATFORM" == "Begge" ]; then
  ANDROID_READY=false

  while ! $ANDROID_READY; do
    if [ ! -f "android/key.properties" ]; then
      SETUP=$(osascript <<EOT
        try
          display alert "🔑 Android Signing Required" message "A release build needs a signing key.

This takes about 1 minute to set up." buttons {"Cancel", "Set Up Now"} default button "Set Up Now" as critical
          return button returned of result
        on error
          return "Cancel"
        end try
EOT
      )
      if [ "$SETUP" == "Cancel" ]; then
        if [ "$PLATFORM" == "Begge" ]; then
          SWITCH=$(osascript <<EOT
            try
              display alert "Skip Android?" message "Build only iOS instead?" buttons {"Cancel All", "Build iOS Only"} default button "Build iOS Only"
              return button returned of result
            on error
              return "Cancel All"
            end try
EOT
          )
          if [ "$SWITCH" == "Build iOS Only" ]; then
            PLATFORM="iOS"
            ANDROID_READY=true
          else
            exit 0
          fi
        else
          exit 0
        fi
      else
        "$RESOURCES/android_setup.sh" "$PROJECT_DIR" "$TOOL_DIR"
        [ -f "android/key.properties" ] && ANDROID_READY=true
      fi
    else
      # Already configured — show and allow change
      CUR_ALIAS=$(grep "keyAlias" android/key.properties 2>/dev/null | sed 's/keyAlias=//')
      CUR_STORE=$(basename "$(grep 'storeFile' android/key.properties 2>/dev/null | sed 's/storeFile=//')" 2>/dev/null)
      KEYACTION=$(osascript <<EOT
        try
          display alert "🔑 Android Signing" message "Current configuration:

    Alias:       $CUR_ALIAS
    Keystore:  $CUR_STORE

Ready to build." buttons {"Change Key", "Continue ▸"} default button "Continue ▸"
          return button returned of result
        on error
          return "Continue ▸"
        end try
EOT
      )
      if [ "$KEYACTION" == "Change Key" ]; then
        "$RESOURCES/android_setup.sh" "$PROJECT_DIR" "$TOOL_DIR"
      else
        ANDROID_READY=true
      fi
    fi
  done
fi

# ════════════════════════════════════════════════════
#  PREVIEW & CONFIRM
# ════════════════════════════════════════════════════
# Calculate new version for preview
CUR_VER="$VERSION"
CUR_BASE=$(echo "$CUR_VER" | sed "s/+[0-9]*$//")
CUR_BLD=$(echo "$CUR_VER" | sed "s/.*+//")
if [ "$BUMP" == "Build +1" ]; then
  PREVIEW_VER="${CUR_BASE}+$(($CUR_BLD + 1))"
else
  P_MAJ=$(echo "$CUR_BASE" | cut -d. -f1)
  P_MIN=$(echo "$CUR_BASE" | cut -d. -f2)
  PREVIEW_VER="${P_MAJ}.$(($P_MIN + 1)).0+$(($CUR_BLD + 1))"
fi

if [ "$PLATFORM" == "Begge" ]; then
  PLAT_TXT="iOS + Android"
else
  PLAT_TXT="$PLATFORM"
fi

CONFIRM=$(osascript <<EOT
  try
    display alert "🚀 Ready to Build" message "
    App:            $APP_NAME
    Version:      $CUR_VER  →  $PREVIEW_VER
    Platform:     $PLAT_TXT

This will update pubspec.yaml and start the build process. A Terminal window will open so you can follow progress." buttons {"Cancel", "Build Now  🔨"} default button "Build Now  🔨"
    return button returned of result
  on error
    return "Cancel"
  end try
EOT
)
if [ "$CONFIRM" == "Cancel" ]; then exit 0; fi

# ════════════════════════════════════════════════════
#  LAUNCH BUILD IN TERMINAL
# ════════════════════════════════════════════════════
osascript <<EOT
  tell application "Terminal"
    activate
    do script "cd '$PROJECT_DIR' && '$RESOURCES/build.sh' '$BUMP' '$PLATFORM' '$PROJECT_DIR'"
    -- Set a nice window title
    delay 0.5
    set custom title of front window to "$APP_NAME — Building $PLAT_TXT..."
  end tell
EOT
