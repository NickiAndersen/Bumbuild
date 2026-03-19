#!/bin/bash
# Universal Flutter Build Tool — Android Signing Setup Wizard
PROJECT_DIR="$1"
TOOL_DIR="$2"
KEYS_DIR="$TOOL_DIR/keys"
cd "$PROJECT_DIR"

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
    # Multiple keystores — show dropdown
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
  if [ -z "$STORE_PASS" ]; then exit 1; fi

  # Validate and get aliases
  ALIAS_LIST=$(keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASS" 2>/dev/null | grep "PrivateKeyEntry\|SecretKeyEntry" | cut -d',' -f1)
  if [ -z "$ALIAS_LIST" ]; then
    osascript -e 'display alert "❌ Invalid Password" message "Wrong password, or no keys found in the keystore file." as critical'
    exit 1
  fi

  ALIAS_COUNT=$(echo "$ALIAS_LIST" | wc -l | tr -d ' ')
  if [ "$ALIAS_COUNT" -eq 1 ]; then
    ALIAS=$(echo "$ALIAS_LIST" | head -1 | xargs)
    osascript -e "display notification \"Using alias: $ALIAS\" with title \"Android Signing\""
  else
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
    if [ -z "$ALIAS" ]; then exit 1; fi
  fi

  KEY_PASS=$(osascript <<EOT
    try
      display dialog "Key password (usually same as keystore):" default answer "$STORE_PASS" with hidden answer with title "🔑 Key Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$KEY_PASS" ]; then exit 1; fi

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
  if [ -z "$STORE_PASS" ]; then exit 1; fi

  ALIAS_LIST=$(keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASS" 2>/dev/null | grep "PrivateKeyEntry\|SecretKeyEntry" | cut -d',' -f1)
  if [ -z "$ALIAS_LIST" ]; then
    osascript -e 'display alert "❌ Invalid Password" message "Wrong password, or no keys found in the keystore file." as critical'
    exit 1
  fi

  ALIAS_COUNT=$(echo "$ALIAS_LIST" | wc -l | tr -d ' ')
  if [ "$ALIAS_COUNT" -eq 1 ]; then
    ALIAS=$(echo "$ALIAS_LIST" | head -1 | xargs)
    osascript -e "display notification \"Found alias: $ALIAS\" with title \"Android Signing\""
  else
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
    if [ -z "$ALIAS" ]; then exit 1; fi
  fi

  KEY_PASS=$(osascript <<EOT
    try
      display dialog "Key password (usually same as keystore):" default answer "$STORE_PASS" with hidden answer with title "🔑 Key Password"
      return text returned of result
    on error
      return ""
    end try
EOT
  )
  if [ -z "$KEY_PASS" ]; then exit 1; fi

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

  if ! command -v keytool &>/dev/null; then
    osascript -e 'display alert "❌ keytool Not Found" message "Java JDK is required to create a keystore. Install it first." as critical'
    exit 1
  fi

  keytool -genkey -v \
    -keystore "$KEYSTORE" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias "$ALIAS" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=$APP_NAME, OU=Mobile, O=$APP_NAME, L=Copenhagen, S=Denmark, C=DK" \
    2>/dev/null

  if [ $? -ne 0 ]; then
    osascript -e 'display alert "❌ Error" message "Could not create keystore." as critical'
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
cat > android/key.properties << KEYEOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
KEYEOF

# ─── Patch build.gradle for release signing ───
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE_GROOVY="android/app/build.gradle"

if [ -f "$GRADLE_KTS" ]; then
  # Kotlin DSL (.kts)
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

    # Replace debug signing with release signing
    sed -i '' 's/signingConfigs.getByName("debug")/signingConfigs.getByName("release")/' "$GRADLE_KTS"
  fi

elif [ -f "$GRADLE_GROOVY" ]; then
  # Groovy DSL (.gradle)
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
            storeFile file(keystoreProperties["storeFile"])\
            storePassword keystoreProperties["storePassword"]\
        }\
    }\
' "$GRADLE_GROOVY"

    # Replace debug signing with release signing
    sed -i '' 's/signingConfigs.debug/signingConfigs.release/' "$GRADLE_GROOVY"
  fi
fi

osascript <<EOT
  display alert "✅ Signing Configured" message "Files created/updated:

  • android/key.properties
  • android/app/build.gradle(.kts)

Ready to build Android release!" as informational
EOT
