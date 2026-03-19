#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║  Universal Flutter Build Tool — Build Runner     ║
# ╚══════════════════════════════════════════════════╝
BUMP="$1"
PLATFORM="$2"
PROJECT_DIR="$3"
cd "$PROJECT_DIR"

# ─── Colors ───
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'
WHITE='\033[1;37m'

# ─── Helpers ───
header() {
  echo ""
  echo -e "${BG_BLUE}${WHITE}                                                    ${RESET}"
  echo -e "${BG_BLUE}${WHITE}  $1  ${RESET}"
  echo -e "${BG_BLUE}${WHITE}                                                    ${RESET}"
  echo ""
}

section() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $1${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

success_banner() {
  echo ""
  echo -e "${BG_GREEN}${WHITE}                                                    ${RESET}"
  echo -e "${BG_GREEN}${WHITE}  ✅  $1  ${RESET}"
  echo -e "${BG_GREEN}${WHITE}                                                    ${RESET}"
  echo ""
}

error_banner() {
  echo ""
  echo -e "${BG_RED}${WHITE}                                                    ${RESET}"
  echo -e "${BG_RED}${WHITE}  ❌  $1  ${RESET}"
  echo -e "${BG_RED}${WHITE}                                                    ${RESET}"
  echo ""
}

elapsed() {
  local secs=$1
  printf '%dm %ds' $((secs / 60)) $((secs % 60))
}

# ─── Find Flutter in PATH ───
if ! command -v flutter &>/dev/null; then
  FLUTTER_PATH=$(bash -l -c 'which flutter' 2>/dev/null)
  if [ -n "$FLUTTER_PATH" ]; then
    export PATH="$(dirname "$FLUTTER_PATH"):$PATH"
  else
    for p in /usr/local/share/flutter/bin /opt/homebrew/bin "$HOME/flutter/bin" "$HOME/development/flutter/bin" "$HOME/fvm/default/bin"; do
      if [ -x "$p/flutter" ]; then
        export PATH="$p:$PATH"
        break
      fi
    done
  fi
fi

if ! command -v flutter &>/dev/null; then
  error_banner "Flutter not found in PATH"
  osascript -e 'display alert "Error" message "Flutter was not found. Make sure Flutter is installed and in your PATH." as critical'
  exit 1
fi

APP_NAME=$(grep "^name:" pubspec.yaml | sed "s/name: *//" | head -1)
FLUTTER_VER=$(flutter --version 2>/dev/null | head -1)

# ═══════════════════════════════════════════════════
#  1. VERSION BUMP
# ═══════════════════════════════════════════════════
CUR=$(grep "^version:" pubspec.yaml | sed "s/version: *//")
BASE=$(echo "$CUR" | sed "s/+[0-9]*$//")
BLD=$(echo "$CUR" | sed "s/.*+//")

if [ "$BUMP" == "Build +1" ]; then
  NEW_VER="${BASE}+$(($BLD + 1))"
else
  MAJ=$(echo "$BASE" | cut -d. -f1)
  MIN=$(echo "$BASE" | cut -d. -f2)
  NEW_VER="${MAJ}.$(($MIN + 1)).0+$(($BLD + 1))"
fi

sed -i.bak "s/^version: .*/version: $NEW_VER/" pubspec.yaml
rm -f pubspec.yaml.bak

# ═══════════════════════════════════════════════════
#  HEADER
# ═══════════════════════════════════════════════════
clear
header "$APP_NAME — Flutter Build"

echo -e "  ${DIM}App${RESET}         ${BOLD}$APP_NAME${RESET}"
echo -e "  ${DIM}Version${RESET}     ${YELLOW}$CUR${RESET}  →  ${GREEN}${BOLD}$NEW_VER${RESET}"
echo -e "  ${DIM}Platform${RESET}    ${BOLD}$PLATFORM${RESET}"
echo -e "  ${DIM}Flutter${RESET}     ${DIM}$FLUTTER_VER${RESET}"
echo -e "  ${DIM}Started${RESET}     $(date '+%H:%M:%S')${RESET}"

mkdir -p build
BUILD_START=$SECONDS
SUCCESS_IOS=true
SUCCESS_ANDROID=true

# ═══════════════════════════════════════════════════
#  2. iOS BUILD
# ═══════════════════════════════════════════════════
if [ "$PLATFORM" == "iOS" ] || [ "$PLATFORM" == "Begge" ]; then
  section "📱 iOS — flutter build ipa --release"
  IOS_START=$SECONDS

  flutter build ipa --release 2>&1 | tee build/ios_build.log
  if [ ${PIPESTATUS[0]} -ne 0 ]; then SUCCESS_IOS=false; fi

  IOS_TIME=$(($SECONDS - $IOS_START))
  if $SUCCESS_IOS; then
    echo -e "\n  ${GREEN}✓ iOS completed in $(elapsed $IOS_TIME)${RESET}"
  else
    echo -e "\n  ${RED}✗ iOS failed after $(elapsed $IOS_TIME)${RESET}"
  fi
fi

# ═══════════════════════════════════════════════════
#  3. ANDROID BUILD
# ═══════════════════════════════════════════════════
if [ "$PLATFORM" == "Android" ] || [ "$PLATFORM" == "Begge" ]; then
  section "🤖 Android — flutter build appbundle --release"
  ANDROID_START=$SECONDS

  flutter build appbundle --release 2>&1 | tee build/android_build.log
  if [ ${PIPESTATUS[0]} -ne 0 ]; then SUCCESS_ANDROID=false; fi

  ANDROID_TIME=$(($SECONDS - $ANDROID_START))
  if $SUCCESS_ANDROID; then
    echo -e "\n  ${GREEN}✓ Android completed in $(elapsed $ANDROID_TIME)${RESET}"
  else
    echo -e "\n  ${RED}✗ Android failed after $(elapsed $ANDROID_TIME)${RESET}"
  fi
fi

# ═══════════════════════════════════════════════════
#  4. RESULTS
# ═══════════════════════════════════════════════════
TOTAL_TIME=$(($SECONDS - $BUILD_START))
HAS_ERROR=false
RESULT_MSG=""
RESULT_LINES=""

if [ "$PLATFORM" == "iOS" ] || [ "$PLATFORM" == "Begge" ]; then
  if $SUCCESS_IOS; then
    RESULT_LINES="${RESULT_LINES}\n  ${GREEN}  ✅  iOS         →  build/ios/ipa/${RESET}"
    open build/ios/ipa/ 2>/dev/null
    RESULT_MSG="iOS: Success ✅"
  else
    RESULT_LINES="${RESULT_LINES}\n  ${RED}  ❌  iOS         →  see build/ios_build.log${RESET}"
    RESULT_MSG="iOS: Failed ❌"
    HAS_ERROR=true
  fi
fi

if [ "$PLATFORM" == "Android" ] || [ "$PLATFORM" == "Begge" ]; then
  if $SUCCESS_ANDROID; then
    RESULT_LINES="${RESULT_LINES}\n  ${GREEN}  ✅  Android  →  build/app/outputs/bundle/release/${RESET}"
    open build/app/outputs/bundle/release/ 2>/dev/null
    RESULT_MSG="${RESULT_MSG}${RESULT_MSG:+\n}Android: Success ✅"
  else
    RESULT_LINES="${RESULT_LINES}\n  ${RED}  ❌  Android  →  see build/android_build.log${RESET}"
    RESULT_MSG="${RESULT_MSG}${RESULT_MSG:+\n}Android: Failed ❌"
    HAS_ERROR=true
  fi
fi

if $HAS_ERROR; then
  error_banner "BUILD FAILED"
else
  success_banner "BUILD COMPLETE"
fi

echo -e "${BOLD}  Summary${RESET}"
echo -e "  ─────────────────────────────────────────"
echo -e "  ${DIM}Version${RESET}     ${BOLD}$NEW_VER${RESET}"
echo -e "  ${DIM}Duration${RESET}    $(elapsed $TOTAL_TIME)"
echo -e "${RESULT_LINES}"
echo -e "  ─────────────────────────────────────────"
echo ""

# ─── Sound + Notification ───
if $HAS_ERROR; then
  afplay /System/Library/Sounds/Basso.aiff 2>/dev/null &
  osascript <<EOT
    display alert "❌ Build Failed" message "$APP_NAME $NEW_VER

$RESULT_MSG

Total time: $(elapsed $TOTAL_TIME)
Check log files in build/ folder." buttons {"Open Logs", "OK"} default button "OK" as critical
    if button returned of result is "Open Logs" then
      tell application "Finder"
        activate
        open POSIX file "$PROJECT_DIR/build/"
      end tell
    end if
EOT
else
  afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
  osascript <<EOT
    display alert "✅ Build Complete!" message "$APP_NAME $NEW_VER

$RESULT_MSG

Total time: $(elapsed $TOTAL_TIME)
Output folders have been opened." buttons {"OK"} default button "OK" as informational
EOT
fi
