#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║  Bumbuild, GUI                                 ║
# ╚══════════════════════════════════════════════════╝
PROJECT_DIR="$1"
RESOURCES="$2"
TOOL_DIR="$3"
cd "$PROJECT_DIR"

APP_NAME=$(grep "^name:" pubspec.yaml | sed "s/name: *//" | head -1)
VERSION=$(grep "^version:" pubspec.yaml | sed "s/version: *//")
BASE_VER=$(echo "$VERSION" | sed "s/+[0-9]*$//")
BUILD_NUM=$(echo "$VERSION" | sed "s/.*+//")

V_MAJ=$(echo "$BASE_VER" | cut -d. -f1)
V_MIN=$(echo "$BASE_VER" | cut -d. -f2)
V_PAT=$(echo "$BASE_VER" | cut -d. -f3)
[ -z "$V_PAT" ] && V_PAT=0

NEXT_BLD=$((BUILD_NUM + 1))

if [ "$V_PAT" -eq 99 ]; then
  NEXT_BUMP_VER="${V_MAJ}.$((V_MIN + 1)).0+${NEXT_BLD}"
else
  NEXT_BUMP_VER="${V_MAJ}.${V_MIN}.$((V_PAT + 1))+${NEXT_BLD}"
fi

HAS_IOS=false
HAS_ANDROID=false
[ -d "ios" ] && HAS_IOS=true
[ -d "android" ] && HAS_ANDROID=true

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

PLAT_INFO=""
$HAS_IOS && PLAT_INFO="iOS"
$HAS_ANDROID && { [ -n "$PLAT_INFO" ] && PLAT_INFO="$PLAT_INFO, Android" || PLAT_INFO="Android"; }

if $HAS_IOS && $HAS_ANDROID; then
  PLAT_BUTTONS='"iOS", "Android", "Both"'
  PLAT_DEFAULT='"Both"'
elif $HAS_IOS; then
  PLAT_BUTTONS='"iOS"'
  PLAT_DEFAULT='"iOS"'
elif $HAS_ANDROID; then
  PLAT_BUTTONS='"Android"'
  PLAT_DEFAULT='"Android"'
else
  osascript -e 'display alert "No Platforms" message "Neither ios/ nor android/ folder found in this project." as critical'
  exit 1
fi

# ════════════════════════════════════════════════════
#  STEP 1, Welcome
# ════════════════════════════════════════════════════
WELCOME=$(osascript <<EOT
  tell application "System Events"
    activate
    set appIcon to missing value
    try
      set appIcon to (POSIX file "$RESOURCES/icon.png") as alias
    end try
  end tell

  set dialogText to "┌─────────────────────────────────┐
│  App            $APP_NAME
│  Version        $VERSION
│  Platforms      $PLAT_INFO
│  Signing        $SIGNING_STATUS
└─────────────────────────────────┘"

  try
    set welcomeChoice to button returned of (display alert "Flutter Build Tool" message dialogText buttons {"Cancel", "Build ▸"} default button "Build ▸")
    return welcomeChoice
  on error
    return "Cancel"
  end try
EOT
)
[ "$WELCOME" == "Cancel" ] && exit 0

# ════════════════════════════════════════════════════
#  STEP 2, Platform
# ════════════════════════════════════════════════════
PLATFORM=$(osascript <<EOT
  try
    set platformChoice to button returned of (display alert "Choose Platform" message "Which platform to build?" buttons {$PLAT_BUTTONS} default button $PLAT_DEFAULT)
    return platformChoice
  on error
    return "Cancel"
  end try
EOT
)
[ "$PLATFORM" == "Cancel" ] && exit 0

# ════════════════════════════════════════════════════
#  STEP 3, Version bump (choose from list)
# ════════════════════════════════════════════════════
BUMP_CHOICE=$(osascript <<EOT
  try
    set choiceList to {"Rebuild       →  $VERSION", "New Version   →  $NEXT_BUMP_VER", "Custom…"}
    set theChoice to choose from list choiceList with prompt "Current version: $VERSION" with title "Version Bump" default items {item 1 of choiceList}
    if theChoice is false then return "Cancel"
    return item 1 of theChoice
  on error
    return "Cancel"
  end try
EOT
)
[ "$BUMP_CHOICE" == "Cancel" ] && exit 0

# ════════════════════════════════════════════════════
#  STEP 3b, Custom version input
# ════════════════════════════════════════════════════
if echo "$BUMP_CHOICE" | grep -q "Custom"; then
  CUSTOM_VER=""
  while [ -z "$CUSTOM_VER" ]; do
    CUSTOM_INPUT=$(osascript <<EOT
      try
        display dialog "Enter version:" default answer "$NEXT_BUMP_VER" with title "Custom Version" buttons {"Cancel", "OK"} default button "OK"
        return text returned of result
      on error
        return "Cancel"
      end try
EOT
    )
    [ "$CUSTOM_INPUT" == "Cancel" ] && exit 0

    if ! echo "$CUSTOM_INPUT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'; then
      osascript -e 'display alert "Invalid Format" message "Use the format: 1.2.3+42" as critical'
      continue
    fi

    CUSTOM_BASE=$(echo "$CUSTOM_INPUT" | sed 's/+[0-9]*$//')
    CUSTOM_BLD=$(echo "$CUSTOM_INPUT" | sed 's/.*+//')

    CUSTOM_MAJ=$(echo "$CUSTOM_BASE" | cut -d. -f1)
    CUSTOM_MIN=$(echo "$CUSTOM_BASE" | cut -d. -f2)
    CUSTOM_PAT=$(echo "$CUSTOM_BASE" | cut -d. -f3)

    if [ "$CUSTOM_MAJ" -lt "$V_MAJ" ] || \
       { [ "$CUSTOM_MAJ" -eq "$V_MAJ" ] && [ "$CUSTOM_MIN" -lt "$V_MIN" ]; } || \
       { [ "$CUSTOM_MAJ" -eq "$V_MAJ" ] && [ "$CUSTOM_MIN" -eq "$V_MIN" ] && [ "$CUSTOM_PAT" -lt "$V_PAT" ]; } || \
       { [ "$CUSTOM_MAJ" -eq "$V_MAJ" ] && [ "$CUSTOM_MIN" -eq "$V_MIN" ] && [ "$CUSTOM_PAT" -eq "$V_PAT" ] && [ "$CUSTOM_BLD" -le "$BUILD_NUM" ]; }; then
       osascript -e "display alert \"Version Too Low\" message \"Must be higher than current version ($VERSION).\" as critical"
      continue
    fi

    CUSTOM_VER=$CUSTOM_INPUT
  done
  BUMP="Custom:${CUSTOM_VER}"
  PREVIEW_VER="$CUSTOM_VER"
elif echo "$BUMP_CHOICE" | grep -q "Rebuild"; then
  BUMP="Rebuild"
  PREVIEW_VER="$VERSION"
else
  BUMP="Bump"
  PREVIEW_VER="$NEXT_BUMP_VER"
fi

# ════════════════════════════════════════════════════
#  STEP 4, Android signing gate
# ════════════════════════════════════════════════════
if [ "$PLATFORM" == "Android" ] || [ "$PLATFORM" == "Both" ]; then
  ANDROID_READY=false

  while ! $ANDROID_READY; do
    if [ ! -f "android/key.properties" ]; then
      SETUP=$(osascript <<EOT
        try
          display alert "Android Signing Required" message "A release build needs a signing key.

This takes about 1 minute to set up." buttons {"Cancel", "Set Up Now"} default button "Set Up Now" as critical
          return button returned of result
        on error
          return "Cancel"
        end try
EOT
      )
      if [ "$SETUP" == "Cancel" ]; then
        if [ "$PLATFORM" == "Both" ]; then
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
        if [ -f "android/key.properties" ]; then
          ANDROID_READY=true
        else
          osascript -e 'display alert "Setup Incomplete" message "Signing was not configured. Make sure Java JDK is installed. Check build/bumbuild.log for details." as critical'
        fi
      fi
    else
      CUR_ALIAS=$(grep "keyAlias" android/key.properties 2>/dev/null | sed 's/keyAlias=//')
      CUR_STORE=$(basename "$(grep 'storeFile' android/key.properties 2>/dev/null | sed 's/storeFile=//')" 2>/dev/null)
      KEYACTION=$(osascript <<EOT
        try
          display alert "Android Signing" message "Current configuration:

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
#  STEP 5, Confirm
# ════════════════════════════════════════════════════
if [ "$PLATFORM" == "Both" ]; then
  PLAT_TXT="iOS + Android"
else
  PLAT_TXT="$PLATFORM"
fi

if [ "$BUMP" == "Rebuild" ]; then
  BUMP_LABEL="No change"
else
  BUMP_LABEL="$VERSION  →  $PREVIEW_VER"
fi

CONFIRM=$(osascript <<EOT
  try
    display alert "Ready to Build" message "
    App:           $APP_NAME
    Version:      $BUMP_LABEL
    Platform:     $PLAT_TXT

This will update pubspec.yaml and start the build in a Terminal window." buttons {"Cancel", "Build Now"} default button "Build Now"
    return button returned of result
  on error
    return "Cancel"
  end try
EOT
)
[ "$CONFIRM" == "Cancel" ] && exit 0

# ════════════════════════════════════════════════════
#  LAUNCH BUILD IN TERMINAL
# ════════════════════════════════════════════════════
osascript <<EOT
  tell application "Terminal"
    activate
    do script "cd '$PROJECT_DIR' && '$RESOURCES/build.sh' '$BUMP' '$PLATFORM' '$PROJECT_DIR'"
    delay 0.5
    set custom title of front window to "$APP_NAME, Building $PLAT_TXT..."
  end tell
EOT
