#!/usr/bin/env bash
set -euo pipefail

# One-command deploy for a physical iPhone.
# You can override defaults via environment variables.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$PROJECT_ROOT/AuraShift.xcodeproj}"
SCHEME="${SCHEME:-AuraShift}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/AuraShiftDerivedDataDevice}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-D-D.AuraShift}"
DEVICE_NAME="${DEVICE_NAME:-iPhone (5)}"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

retry() {
  local attempts="$1"
  shift
  local n=1
  until "$@"; do
    if (( n >= attempts )); then
      return 1
    fi
    log "Retry $((n + 1))/$attempts: $*"
    sleep 1
    ((n++))
  done
}

# Optional explicit IDs (override auto-detection).
DEVICE_UDID="${DEVICE_UDID:-}"
COREDEVICE_ID="${COREDEVICE_ID:-}"

if [[ -z "$DEVICE_UDID" ]]; then
  DEVICE_UDID="$(xcrun xctrace list devices | awk -v name="$DEVICE_NAME" '
    index($0, name " (") == 1 {
      line = $0
      sub(/^.*\(/, "", line)
      sub(/\)$/, "", line)
      print line
      exit
    }
  ')"
fi

if [[ -z "$COREDEVICE_ID" ]]; then
  COREDEVICE_ID="$(xcrun devicectl list devices | awk -v name="$DEVICE_NAME" '
    index($0, name) == 1 && $0 ~ /available/ {
      for (i = 1; i <= NF; i++) {
        candidate = $i
        if (length(candidate) == 36) {
          probe = candidate
          gsub(/[0-9A-F-]/, "", probe)
          if (length(probe) == 0 && index(candidate, "-") > 0) {
            print candidate
            exit
          }
        }
      }
    }
  ')"
fi

if [[ -z "$DEVICE_UDID" ]]; then
  echo "Error: iOS destination UDID was not found for '$DEVICE_NAME'." >&2
  echo "Tip: set DEVICE_UDID manually and retry." >&2
  exit 1
fi

if [[ -z "$COREDEVICE_ID" ]]; then
  echo "Error: CoreDevice identifier was not found for '$DEVICE_NAME'." >&2
  echo "Tip: set COREDEVICE_ID manually and retry." >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/AuraShift.app"

log "Building $SCHEME for device $DEVICE_NAME ($DEVICE_UDID)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at '$APP_PATH'." >&2
  exit 1
fi

log "Installing app on device ($COREDEVICE_ID)..."
retry 3 xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP_PATH"

log "Launching $APP_BUNDLE_ID..."
retry 3 xcrun devicectl device process launch --device "$COREDEVICE_ID" "$APP_BUNDLE_ID"

log "Done. App is running on $DEVICE_NAME."
