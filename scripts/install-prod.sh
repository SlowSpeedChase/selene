#!/bin/bash
# install-prod.sh — Generate com.selene.prod.* launchd plists from the canonical
# launchd/com.selene.*.plist files by per-key substitution.
#
# Single source of truth: the canonical dev plists in launchd/ run the TypeScript
# sources via ts-node wrapper scripts. This script renders production variants that
# run the COMPILED output (node <PROD_DIR>/dist/...) so we never commit duplicate
# prod plists that drift from the canonical ones.
#
# This task only GENERATES and LINTS plists. It never touches the live launchd
# domain unless invoked WITHOUT --dry-run and WITHOUT --no-load.

set -euo pipefail

# --- Resolve the canonical launchd/ dir relative to this script -------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHD_DIR="${SCRIPT_DIR}/launchd"

# --- Defaults / CLI flags ----------------------------------------------------
PROD_DIR="${HOME}/selene-prod"
OUT_DIR="${HOME}/Library/LaunchAgents"
LABEL_PREFIX="com.selene.prod."
DRY_RUN=0
NO_LOAD=0

# The canonical plists hardcode the main checkout path. This is the literal
# string we substitute FROM — NOT this script's location (it runs from a
# worktree whose path will not match what is written in the plists).
SRC_PREFIX="/Users/chaseeasterling/selene"

usage() {
    cat <<'EOF'
Usage: install-prod.sh [options]

Generates com.selene.prod.* plists from launchd/com.selene.*.plist.

Options:
  --prod-dir DIR        Production deploy dir (default: $HOME/selene-prod)
  --out DIR             Output dir for plists (default: $HOME/Library/LaunchAgents)
  --label-prefix PFX    Label prefix (default: com.selene.prod.)
  --dry-run             Print what would be written; write nothing
  --no-load             Generate files but do NOT run launchctl bootout/bootstrap
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prod-dir)      PROD_DIR="$2"; shift 2 ;;
        --out)           OUT_DIR="$2"; shift 2 ;;
        --label-prefix)  LABEL_PREFIX="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=1; shift ;;
        --no-load)       NO_LOAD=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# --- Resolve an absolute node path (launchd does not resolve bare 'node') ----
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
    # Fall back to the conventional Homebrew location used by the dev wrappers.
    NODE_BIN="/usr/local/bin/node"
fi

# --- Helpers -----------------------------------------------------------------
# Rewrite a path that begins with SRC_PREFIX so it begins with PROD_DIR instead.
# Anchored to the start of the string, so /Users/.../selene-data is NOT matched.
remap_path() {
    local val="$1"
    if [[ "$val" == "${SRC_PREFIX}/"* ]]; then
        printf '%s' "${PROD_DIR}/${val#"${SRC_PREFIX}"/}"
    elif [[ "$val" == "${SRC_PREFIX}" ]]; then
        printf '%s' "${PROD_DIR}"
    else
        printf '%s' "$val"
    fi
}

if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$OUT_DIR"
fi

shopt -s nullglob
generated_count=0

for src in "${LAUNCHD_DIR}"/com.selene.*.plist; do
    base="$(basename "$src")"          # com.selene.<name>.plist

    # Skip any source already carrying the prod prefix to avoid double-transform.
    if [[ "$base" == com.selene.prod.* ]]; then
        continue
    fi

    name="${base#com.selene.}"         # <name>.plist
    name="${name%.plist}"              # <name>

    new_label="${LABEL_PREFIX}${name}"
    dest="${OUT_DIR}/com.selene.prod.${name}.plist"

    # Determine the compiled entrypoint. server is special (not under workflows/).
    if [[ "$name" == "server" ]]; then
        prog_target="${PROD_DIR}/dist/server.js"
    else
        prog_target="${PROD_DIR}/dist/workflows/${name}.js"
    fi

    # Read existing path-valued keys from the source so we can remap them.
    src_wd="$(/usr/libexec/PlistBuddy -c 'Print :WorkingDirectory' "$src" 2>/dev/null || true)"
    src_out="$(/usr/libexec/PlistBuddy -c 'Print :StandardOutPath' "$src" 2>/dev/null || true)"
    src_err="$(/usr/libexec/PlistBuddy -c 'Print :StandardErrorPath' "$src" 2>/dev/null || true)"

    new_wd="$(remap_path "$src_wd")"
    new_out="$(remap_path "$src_out")"
    new_err="$(remap_path "$src_err")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[dry-run] would write ${dest}"
        echo "          Label             = ${new_label}"
        echo "          ProgramArguments  = ${NODE_BIN} ${prog_target}"
        [[ -n "$src_wd" ]]  && echo "          WorkingDirectory  = ${new_wd}"
        [[ -n "$src_out" ]] && echo "          StandardOutPath   = ${new_out}"
        [[ -n "$src_err" ]] && echo "          StandardErrorPath = ${new_err}"
        echo "          EnvironmentVariables.SELENE_ENV = production"
        continue
    fi

    # Copy the canonical plist, then edit per-key. Per-key edits preserve
    # KeepAlive / RunAtLoad / StartInterval / other env vars (e.g.
    # SELENE_DB_PATH) untouched, and avoid any substring corruption.
    cp "$src" "$dest"

    plutil -replace Label -string "$new_label" "$dest"

    # Rebuild ProgramArguments entirely: invoke node with the compiled target.
    # This intentionally drops the dev wrapper-script indirection (ts-node).
    plutil -replace ProgramArguments -json "[\"${NODE_BIN}\", \"${prog_target}\"]" "$dest"

    [[ -n "$src_wd" ]]  && plutil -replace WorkingDirectory  -string "$new_wd"  "$dest"
    [[ -n "$src_out" ]] && plutil -replace StandardOutPath   -string "$new_out" "$dest"
    [[ -n "$src_err" ]] && plutil -replace StandardErrorPath -string "$new_err" "$dest"

    # Inject SELENE_ENV=production. Create the env dict only if it is absent
    # (in the canonical plists it already exists, so this is normally a no-op).
    if ! plutil -extract EnvironmentVariables xml1 -o /dev/null "$dest" 2>/dev/null; then
        plutil -insert EnvironmentVariables -xml '<dict/>' "$dest" 2>/dev/null || true
    fi
    plutil -replace EnvironmentVariables.SELENE_ENV -string production "$dest"

    echo "wrote ${dest}"
    generated_count=$((generated_count + 1))

    # Load into the live launchd domain only when explicitly requested.
    if [[ "$NO_LOAD" -eq 0 ]]; then
        uid="$(id -u)"
        launchctl bootout "gui/${uid}/${new_label}" 2>/dev/null || true
        launchctl bootstrap "gui/${uid}" "$dest"
    fi
done

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "Generated ${generated_count} plist(s) into ${OUT_DIR}"
fi
