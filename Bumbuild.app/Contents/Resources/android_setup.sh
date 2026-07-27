#!/bin/bash
# Universal Flutter Build Tool, Android Signing Setup Wizard
PROJECT_DIR="$1"
TOOL_DIR="$2"
KEYS_DIR="$TOOL_DIR/keys"
cd "$PROJECT_DIR"

echo "=== Bumbuild Android Signing Setup ==="
echo "Project: $PROJECT_DIR"
echo "Tool dir: $TOOL_DIR"

# Find Java keytool in PATH or common locations
if ! command -v keytool &>/dev/null; then
  echo "keytool not in PATH, searching..."
  KTPATH=""
  for jdk_root in /usr/bin /opt/homebrew/opt/openjdk*/bin /usr/local/opt/openjdk*/bin /Library/Java/JavaVirtualMachines/*/Contents/Home/bin; do
    for kt in "$jdk_root"/keytool; do
      if [ -x "$kt" ]; then
        KTPATH="$jdk_root"
        export PATH="$KTPATH:$PATH"
        break 2
      fi
    done
  done
  if [ -z "$KTPATH" ]; then
    LOGIN_KT=$(bash -l -c 'which keytool' 2>/dev/null)
    if [ -n "$LOGIN_KT" ]; then
      export PATH="$(dirname "$LOGIN_KT"):$PATH"
      echo "Found via login shell: $(which keytool)"
    fi
  else
    echo "Found keytool at: $(which keytool)"
  fi
fi

if ! command -v keytool &>/dev/null; then
  echo "ERROR: keytool not found after searching common locations"
  osascript -e 'display alert "keytool Not Found" message "Java JDK is required to manage keystores. Install it first." as critical'
  exit 1
fi
echo "keytool: $(which keytool)"

APP_NAME=$(grep "^name:" pubspec.yaml | sed "s/name: *//" | head -1)
mkdir -p "$KEYS_DIR"

# ─── Scan keys/ folder for existing keystores ───
FOUND_KEYS=""
FOUND_COUNT=0
for f in "$KEYS_DIR"/*.jks "$KEYS_DIR"/*.keystore; do
  [ -f "$f" ] || continue
  FOUND_KEYS="$FOUND_KEYS$f"$'\n'
  FOUND_COUNT=$((FOUND_COUNT + 1))
done
FOUND_KEYS=$(echo "$FOUND_KEYS" | sed '/^$/d')
echo "Found $FOUND_COUNT keystore(s) in keys/"

# ─── Step 1: Choose source ───
if [ "$FOUND_COUNT" -gt 0 ]; then
  # Build a display list of found keys
  KEY_NAMES=""
  while IFS= read -r kf; do
    KEY_NAMES="${KEY_NAMES}  • $(basename "$kf")"$'\n'
  done <<< "$FOUND_KEYS"

  HAS_KEY=$(osascript <<EOT
    try
      display alert "🔑 Android Signing Setup" message "$APP_NAME needs a signing key.

Found in keys/ folder:
$KEY_NAMES
Choose how to proceed:" buttons {"Browse Other...", "Create New", "Use from keys/"} default button "Use from keys/"
      return button returned of result
    on error
      return "Cancel"
    end try
EOT
  )
else
  HAS_KEY=$(osascript <<EOT
    try
      display alert "🔑 Android Signing Setup" message "$APP_NAME needs a signing key for release builds.

No keystores found in keys/ folder yet.
New keystores will be saved there automatically." buttons {"Cancel", "Choose Existing", "Create New"} default button "Create New"
      return button returned of result
    on error
      return "Cancel"
    end try
EOT
  )
fi

if [ "$HAS_KEY" == "Cancel" ]; then exit 1; fi

# ═══════════════════════════════════════════════════
#  USE FROM keys/ FOLDER
# ═══════════════════════════════════════════════════
if [ "$HAS_KEY" == "Use from keys/" ]; then
  if [ "$FOUND_COUNT" -eq 1 ]; then
    KEYSTORE=$(echo "$FOUND_KEYS" | head -1)
  else
    # Multiple keystores, show dropdown
    APPLESCRIPT_KLIST=""
    FIRST_KEY=""
    while IFS= read -r kf; do
      kname=$(basename "$kf")
      [ -z "$FIRST_KEY" ] && FIRST_KEY="$kname"
      [ -n "$APPLESCRIPT_KLIST" ] && APPLESCRIPT_KLIST="$APPLESCRIPT_KLIST, "
      APPLESCRIPT_KLIST="$APPLESCRIPT_KLIST\"$kname\""
    done <<< "$FOUND_KEYS"

    CHOSEN=$(osascript <<EOT
      try
        choose from list {$APPLESCRIPT_KLIST} with prompt "Select keystore to use:" with title "🔑 Select Keystore" default items {"$FIRST_KEY"}
        if result is false then return ""
        return item 1 of result
      on error
        return ""
      end try
EOT
    )
    if [ -z "$CHOSEN" ]; then exit 1; fi
    KEYSTORE="$KEYS_DIR/$CHOSEN"
  fi

  # Ask for password
  STORE_PASS=$(osascript <<EOT
    try
      display dialog "Enter keystore password for $(basename "$KEYSTORE"):" default answer "" with hidden answer with title "🔑 Keystore Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$STORE_PASS" ]; then echo "ERROR: no password"; exit 1; fi

  # Validate and get aliases
  echo "Validating keystore: $KEYSTORE"
  KEYTOOL_OUT=$(keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASS" 2>/dev/null)
  KEYTOOL_EXIT=$?
  echo "keytool exit code: $KEYTOOL_EXIT"
  mkdir -p build
  ALIAS_LIST=$(echo "$KEYTOOL_OUT" | grep "PrivateKeyEntry\|SecretKeyEntry" | cut -d',' -f1)
  if [ -z "$ALIAS_LIST" ]; then
    if [ "$KEYTOOL_EXIT" -ne 0 ]; then
      echo "ERROR: keytool validation failed (exit $KEYTOOL_EXIT)"
      osascript -e 'display alert "Invalid Password" message "The password is incorrect, or the keystore file is corrupted." as critical'
    else
      osascript -e 'display alert "No Keys Found" message "The keystore file does not contain any private key entries." as critical'
    fi
    exit 1
  fi

  ALIAS_COUNT=$(echo "$ALIAS_LIST" | wc -l | tr -d ' ')
  echo "Found $ALIAS_COUNT alias(es)"
  if [ "$ALIAS_COUNT" -eq 1 ]; then
    ALIAS=$(echo "$ALIAS_LIST" | head -1 | xargs)
    echo "Auto-selected alias: $ALIAS"
    osascript -e "display notification \"Using alias: $ALIAS\" with title \"Android Signing\""
  else
    echo "Multiple aliases, showing selection dialog..."
    APPLESCRIPT_LIST=""
    FIRST=""
    while IFS= read -r line; do
      a=$(echo "$line" | xargs)
      [ -z "$FIRST" ] && FIRST="$a"
      [ -n "$APPLESCRIPT_LIST" ] && APPLESCRIPT_LIST="$APPLESCRIPT_LIST, "
      APPLESCRIPT_LIST="$APPLESCRIPT_LIST\"$a\""
    done <<< "$ALIAS_LIST"

    ALIAS=$(osascript <<EOT
      try
        choose from list {$APPLESCRIPT_LIST} with prompt "Multiple keys found. Select the one to use for signing:" with title "🔑 Select Key Alias" default items {"$FIRST"}
        if result is false then return ""
        return item 1 of result
      on error
        return ""
      end try
EOT
    )
    echo "Raw ALIAS from AppleScript: [$ALIAS]"
    ALIAS=$(echo "$ALIAS" | xargs)
    echo "Trimmed ALIAS: [$ALIAS]"
    if [ -z "$ALIAS" ]; then echo "ERROR: no alias selected"; exit 1; fi
    echo "Selected alias: $ALIAS"
  fi

  echo "Prompting for key password..."
  KEY_PASS=$(osascript <<EOT
    try
      display dialog "Key password (usually same as keystore):" default answer "$STORE_PASS" with hidden answer with title "🔑 Key Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$KEY_PASS" ]; then echo "ERROR: no key password"; exit 1; fi
  echo "Key password entered"

# ═══════════════════════════════════════════════════
#  CHOOSE EXISTING FILE (Browse)
# ═══════════════════════════════════════════════════
elif [ "$HAS_KEY" == "Choose Existing" ] || [ "$HAS_KEY" == "Browse Other..." ]; then
  KEYSTORE=$(osascript <<EOT
    try
      set f to choose file with prompt "Select your keystore file (.jks / .keystore)" of type {"jks", "keystore", ""}
      return POSIX path of f
    on error
      return ""
    end try
EOT
  )
  if [ -z "$KEYSTORE" ]; then exit 1; fi

  STORE_PASS=$(osascript <<EOT
    try
      display dialog "Enter keystore password:" default answer "" with hidden answer with title "🔑 Keystore Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$STORE_PASS" ]; then echo "ERROR: no password"; exit 1; fi

  # Validate and get aliases
  echo "Validating keystore: $KEYSTORE"
  KEYTOOL_OUT=$(keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASS" 2>/dev/null)
  KEYTOOL_EXIT=$?
  echo "keytool exit code: $KEYTOOL_EXIT"
  mkdir -p build
  ALIAS_LIST=$(echo "$KEYTOOL_OUT" | grep "PrivateKeyEntry\|SecretKeyEntry" | cut -d',' -f1)
  if [ -z "$ALIAS_LIST" ]; then
    if [ "$KEYTOOL_EXIT" -ne 0 ]; then
      echo "ERROR: keytool validation failed (exit $KEYTOOL_EXIT)"
      osascript -e 'display alert "Invalid Password" message "The password is incorrect, or the keystore file is corrupted." as critical'
    else
      osascript -e 'display alert "No Keys Found" message "The keystore file does not contain any private key entries." as critical'
    fi
    exit 1
  fi

  ALIAS_COUNT=$(echo "$ALIAS_LIST" | wc -l | tr -d ' ')
  echo "Found $ALIAS_COUNT alias(es)"
  if [ "$ALIAS_COUNT" -eq 1 ]; then
    ALIAS=$(echo "$ALIAS_LIST" | head -1 | xargs)
    echo "Auto-selected alias: $ALIAS"
    osascript -e "display notification \"Found alias: $ALIAS\" with title \"Android Signing\""
  else
    echo "Multiple aliases, showing selection dialog..."
    APPLESCRIPT_LIST=""
    FIRST=""
    while IFS= read -r line; do
      a=$(echo "$line" | xargs)
      [ -z "$FIRST" ] && FIRST="$a"
      [ -n "$APPLESCRIPT_LIST" ] && APPLESCRIPT_LIST="$APPLESCRIPT_LIST, "
      APPLESCRIPT_LIST="$APPLESCRIPT_LIST\"$a\""
    done <<< "$ALIAS_LIST"

    ALIAS=$(osascript <<EOT
      try
        choose from list {$APPLESCRIPT_LIST} with prompt "Multiple keys found. Select the one to use for signing:" with title "🔑 Select Key Alias" default items {"$FIRST"}
        if result is false then return ""
        return item 1 of result
      on error
        return ""
      end try
EOT
    )
    echo "Raw ALIAS from AppleScript: [$ALIAS]"
    ALIAS=$(echo "$ALIAS" | xargs)
    echo "Trimmed ALIAS: [$ALIAS]"
    if [ -z "$ALIAS" ]; then echo "ERROR: no alias selected"; exit 1; fi
    echo "Selected alias: $ALIAS"
  fi

  echo "Prompting for key password..."
  KEY_PASS=$(osascript <<EOT
    try
      display dialog "Key password (usually same as keystore):" default answer "$STORE_PASS" with hidden answer with title "🔑 Key Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$KEY_PASS" ]; then echo "ERROR: no key password"; exit 1; fi
  echo "Key password entered"

  # Offer to copy into keys/ folder for portability
  KEYSTORE_NAME=$(basename "$KEYSTORE")
  if [ "$(dirname "$KEYSTORE")" != "$KEYS_DIR" ]; then
    COPY_IT=$(osascript <<EOT
      try
        display alert "📂 Copy to keys/ folder?" message "Copying $KEYSTORE_NAME into the keys/ folder keeps everything together and makes it portable across projects.

Copy now?" buttons {"No, use original path", "Yes, copy"} default button "Yes, copy"
        return button returned of result
      on error
        return "No, use original path"
      end try
EOT
    )
    if [ "$COPY_IT" == "Yes, copy" ]; then
      cp "$KEYSTORE" "$KEYS_DIR/$KEYSTORE_NAME"
      KEYSTORE="$KEYS_DIR/$KEYSTORE_NAME"
    fi
  fi

# ═══════════════════════════════════════════════════
#  CREATE NEW KEYSTORE (saved to keys/)
# ═══════════════════════════════════════════════════
else
  STORE_PASS=$(osascript <<EOT
    try
      display dialog "Choose a password for your new keystore (min. 6 characters):" default answer "" with hidden answer with title "🔑 New Keystore"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$STORE_PASS" ] || [ ${#STORE_PASS} -lt 6 ]; then
    osascript -e 'display alert "❌ Invalid Password" message "Password must be at least 6 characters." as critical'
    exit 1
  fi

  KEY_PASS="$STORE_PASS"
  ALIAS="upload"
  KEYSTORE="$KEYS_DIR/upload-keystore.jks"

  # Avoid overwriting existing keystore
  if [ -f "$KEYSTORE" ]; then
    COUNTER=2
    while [ -f "$KEYS_DIR/upload-keystore-${COUNTER}.jks" ]; do
      COUNTER=$((COUNTER + 1))
    done
    KEYSTORE="$KEYS_DIR/upload-keystore-${COUNTER}.jks"
  fi

  KEYTOOL_OUT=$(keytool -genkey -v \
    -keystore "$KEYSTORE" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias "$ALIAS" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=$APP_NAME, O=$APP_NAME" \
    2>/dev/null)
  KEYTOOL_EXIT=$?

  if [ $KEYTOOL_EXIT -ne 0 ]; then
    osascript -e 'display alert "Keystore Failed" message "Could not create the keystore. Check that Java JDK is installed." as critical'
    exit 1
  fi

  osascript <<EOT
    display alert "✅ Keystore Created" message "Saved to:
$(basename "$KEYSTORE") in keys/ folder

⚠️  IMPORTANT: Back up the keys/ folder safely!
The keystore is required for all future updates to Google Play Store." as informational
EOT
fi

# ─── Create key.properties ───
echo "Writing android/key.properties..."
cat > android/key.properties << KEYEOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
KEYEOF
echo "key.properties created"

# ─── Patch build.gradle for release signing ───
echo "Patching build.gradle for release signing..."
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE_GROOVY="android/app/build.gradle"

# When BOTH .gradle and .gradle.kts exist, Gradle uses the Groovy (.gradle) file.
# We must detect this conflict and patch the file Gradle actually uses.
if [ -f "$GRADLE_GROOVY" ] && [ -f "$GRADLE_KTS" ]; then
  echo "⚠️  Both build.gradle and build.gradle.kts found, Gradle uses build.gradle"
fi

# ─── Patch Groovy build.gradle (Gradle prefers this when both exist) ───
if [ -f "$GRADLE_GROOVY" ]; then
  if ! grep -q "key.properties" "$GRADLE_GROOVY"; then
    cp "$GRADLE_GROOVY" "${GRADLE_GROOVY}.bak"

    # Insert keystore loading BEFORE "android {" block
    sed -i '' '/^android {/i\
\
def keystoreProperties = new Properties()\
def keystorePropertiesFile = rootProject.file("key.properties")\
if (keystorePropertiesFile.exists()) {\
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\
}\
' "$GRADLE_GROOVY"

    # Insert signingConfigs BEFORE "buildTypes {" block
    sed -i '' '/buildTypes {/i\
    signingConfigs {\
        release {\
            keyAlias keystoreProperties["keyAlias"]\
            keyPassword keystoreProperties["keyPassword"]\
            storeFile keystoreProperties["storeFile"] ? file(keystoreProperties["storeFile"]) : null\
            storePassword keystoreProperties["storePassword"]\
        }\
    }\
' "$GRADLE_GROOVY"
  fi

  # Always ensure release signing is used (even if file was previously patched)
  if grep -q 'signingConfigs.debug' "$GRADLE_GROOVY"; then
    sed -i '' 's/signingConfigs.debug/signingConfigs.release/g' "$GRADLE_GROOVY"
  fi

  # Verify signing was correctly configured
  if ! grep -q 'signingConfigs.release' "$GRADLE_GROOVY"; then
    if grep -q 'buildTypes' "$GRADLE_GROOVY" && grep -q 'signingConfigs' "$GRADLE_GROOVY"; then
      sed -i '' '/release {/a\
            signingConfig signingConfigs.release
' "$GRADLE_GROOVY"
    fi
  fi

  if ! grep -q 'signingConfigs.release' "$GRADLE_GROOVY"; then
    osascript -e 'display alert "⚠️ Signing Warning" message "Could not automatically configure release signing in build.gradle. You may need to set signingConfig manually." as critical'
  fi
fi

# ─── Also patch .kts if it exists (so both files stay in sync) ───
if [ -f "$GRADLE_KTS" ]; then
  if ! grep -q "key.properties" "$GRADLE_KTS"; then
    cp "$GRADLE_KTS" "${GRADLE_KTS}.bak"

    # Insert imports at top of file
    sed -i '' '1i\
import java.util.Properties\
import java.io.FileInputStream\
' "$GRADLE_KTS"

    # Insert keystore loading BEFORE "android {" block
    sed -i '' '/^android {/i\
\
val keystorePropertiesFile = rootProject.file("key.properties")\
val keystoreProperties = Properties()\
if (keystorePropertiesFile.exists()) {\
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\
}\
' "$GRADLE_KTS"

    # Insert signingConfigs BEFORE "buildTypes {" block
    sed -i '' '/buildTypes {/i\
    signingConfigs {\
        create("release") {\
            keyAlias = keystoreProperties["keyAlias"] as String?\
            keyPassword = keystoreProperties["keyPassword"] as String?\
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }\
            storePassword = keystoreProperties["storePassword"] as String?\
        }\
    }\
' "$GRADLE_KTS"
  fi

  # Always ensure release signing is used (even if file was previously patched)
  if grep -q 'signingConfigs.getByName("debug")' "$GRADLE_KTS"; then
    sed -i '' 's/signingConfigs.getByName("debug")/signingConfigs.getByName("release")/g' "$GRADLE_KTS"
  fi

  # Verify signing was correctly configured
  if ! grep -q 'signingConfigs.getByName("release")' "$GRADLE_KTS"; then
    if grep -q 'buildTypes' "$GRADLE_KTS" && grep -q 'signingConfigs' "$GRADLE_KTS"; then
      sed -i '' '/release {/a\
            signingConfig = signingConfigs.getByName("release")
' "$GRADLE_KTS"
    fi
  fi

  # Only warn for .kts if .gradle doesn't exist (otherwise .gradle is the one that matters)
  if [ ! -f "$GRADLE_GROOVY" ] && ! grep -q 'signingConfigs.getByName("release")' "$GRADLE_KTS"; then
    osascript -e 'display alert "⚠️ Signing Warning" message "Could not automatically configure release signing in build.gradle.kts. You may need to set signingConfig manually." as critical'
  fi
fi

if [ ! -f "$GRADLE_GROOVY" ] && [ ! -f "$GRADLE_KTS" ]; then
  osascript -e 'display alert "⚠️ No build.gradle" message "Neither build.gradle nor build.gradle.kts was found in android/app/. Signing config could not be applied." as critical'
fi

osascript <<EOT
  display alert "✅ Signing Configured" message "Files created/updated:

  • android/key.properties
  • android/app/build.gradle(.kts)

Ready to build Android release!" as informational
EOT
echo "Signing setup complete"
