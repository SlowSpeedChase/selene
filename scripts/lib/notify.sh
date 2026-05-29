# notify.sh — sourced helper for deploy notifications.
#
# Provides: selene_notify "title" "message"
#   (a) appends a timestamped line to the deploy log
#       (${SELENE_DEPLOY_LOG:-$HOME/selene-prod/deploy.log}, dir created if missing)
#   (b) fires a best-effort macOS notification via osascript.
#
# Dependency-free. Sourcing this file must NOT mutate the parent shell's
# options (no `set -e` etc.) and must never fail the deploy if osascript errors.

selene_notify() {
    local title="${1:-Selene}"
    local message="${2:-}"

    local log="${SELENE_DEPLOY_LOG:-$HOME/selene-prod/deploy.log}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || true

    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s  [%s] %s\n' "$ts" "$title" "$message" >>"$log" 2>/dev/null || true

    # Sanitize for the osascript string literal: embedded double-quotes would
    # otherwise terminate the AppleScript string. Swap them for single quotes.
    local safe_title="${title//\"/\'}"
    local safe_message="${message//\"/\'}"

    # Best-effort; never fail the deploy if osascript is unavailable or errors.
    osascript -e "display notification \"${safe_message}\" with title \"${safe_title}\"" >/dev/null 2>&1 || true
}
