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
DB_PATH_OVERRIDE=""

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
  --label-prefix PFX    Label prefix (default: com.selene.prod.). Also used as
                        the output plist FILENAME prefix.
  --db-path PATH        Override SELENE_DB_PATH in every generated plist (for
                        staging/test loads against an isolated DB). When omitted,
                        the canonical (real prod) SELENE_DB_PATH is preserved.
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
        --db-path)       DB_PATH_OVERRIDE="$2"; shift 2 ;;
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

# The dest filename prefix is the SAME label prefix used for each plist's Label,
# and is the basis for both generation and the orphan-reconcile scan, so the
# filename, Label, reconcile glob, and skip-guard cannot drift from one another.
DEST_PREFIX="$LABEL_PREFIX"

# Labels that must NEVER be pruned by reconcile. The deploy-watcher prod plist
# is infra installed separately (it has no workflow source under launchd/), so
# it must not be booted out or removed here.
RECONCILE_SKIP=("${LABEL_PREFIX}deploy-watcher")

shopt -s nullglob

# Track generated <name>s and their dest paths/labels across the two passes.
generated_names=()
generated_dests=()
generated_labels=()

# Clean up any leftover temp file on hard failure.
TMP_PLIST=""
cleanup_tmp() { [[ -n "$TMP_PLIST" && -f "$TMP_PLIST" ]] && rm -f "$TMP_PLIST"; return 0; }
trap cleanup_tmp EXIT

# === Pass 1: generate ALL plists ============================================
# Each plist is built into a temp file and only mv'd into place after a
# successful plutil -lint. If ANY generation fails, the script exits non-zero
# BEFORE Pass 2, so launchd is never touched with an incomplete prod set.
for src in "${LAUNCHD_DIR}"/com.selene.*.plist; do
    base="$(basename "$src")"          # com.selene.<name>.plist

    # Skip any source already carrying the prod prefix to avoid double-transform.
    if [[ "$base" == com.selene.prod.* ]]; then
        continue
    fi

    name="${base#com.selene.}"         # <name>.plist
    name="${name%.plist}"              # <name>

    new_label="${LABEL_PREFIX}${name}"
    dest="${OUT_DIR}/${DEST_PREFIX}${name}.plist"

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

    # Record the generated set in ALL modes (needed for the would-prune print
    # under --dry-run / --no-load as well as the real load/reconcile paths).
    generated_names+=("$name")
    generated_dests+=("$dest")
    generated_labels+=("$new_label")

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

    # Build into a temp file, then atomically mv into place. Per-key edits
    # preserve KeepAlive / RunAtLoad / StartInterval / other env vars (e.g.
    # SELENE_DB_PATH) untouched, and avoid any substring corruption. Building
    # in a temp file means a failed plutil never leaves a half-edited dest.
    TMP_PLIST="$(mktemp)"
    cp "$src" "$TMP_PLIST"

    plutil -replace Label -string "$new_label" "$TMP_PLIST"

    # Rebuild ProgramArguments entirely: invoke node with the compiled target.
    # This intentionally drops the dev wrapper-script indirection (ts-node).
    plutil -replace ProgramArguments -json "[\"${NODE_BIN}\", \"${prog_target}\"]" "$TMP_PLIST"

    [[ -n "$src_wd" ]]  && plutil -replace WorkingDirectory  -string "$new_wd"  "$TMP_PLIST"
    [[ -n "$src_out" ]] && plutil -replace StandardOutPath   -string "$new_out" "$TMP_PLIST"
    [[ -n "$src_err" ]] && plutil -replace StandardErrorPath -string "$new_err" "$TMP_PLIST"

    # Inject SELENE_ENV=production. Create the env dict only if it is absent
    # (in the canonical plists it already exists, so this is normally a no-op).
    if ! plutil -extract EnvironmentVariables xml1 -o /dev/null "$TMP_PLIST" 2>/dev/null; then
        plutil -insert EnvironmentVariables -xml '<dict/>' "$TMP_PLIST" 2>/dev/null || true
    fi
    plutil -replace EnvironmentVariables.SELENE_ENV -string production "$TMP_PLIST"

    # Optional --db-path override: point the generated plist at an isolated DB
    # (staging/test). When the flag is absent this is skipped, so the canonical
    # (real prod) SELENE_DB_PATH is inherited unchanged.
    [[ -n "$DB_PATH_OVERRIDE" ]] && \
        plutil -replace EnvironmentVariables.SELENE_DB_PATH -string "$DB_PATH_OVERRIDE" "$TMP_PLIST"

    # Validate before committing. A lint failure aborts the whole run (set -e
    # plus explicit exit) so Pass 2 never runs with an incomplete prod set.
    if ! plutil -lint "$TMP_PLIST" >/dev/null; then
        echo "ERROR: generated plist failed lint for ${new_label}; aborting before any launchctl." >&2
        rm -f "$TMP_PLIST"; TMP_PLIST=""
        exit 1
    fi

    mv "$TMP_PLIST" "$dest"
    TMP_PLIST=""
    echo "wrote ${dest}"
done

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "Generated ${#generated_names[@]} plist(s) into ${OUT_DIR}"
fi

# === Reconcile: prune orphaned prod plists ==================================
# A <name> present in OUT_DIR but no longer produced by launchd/ should stop
# running in prod. On the real load path we bootout + rm orphans; under
# --dry-run / --no-load we only PRINT what would be pruned (OUT_DIR may be an
# arbitrary temp dir, so deleting there would be wrong).
in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
    return 1
}

uid="$(id -u)"
for existing in "${OUT_DIR}/${DEST_PREFIX}"*.plist; do
    ex_base="$(basename "$existing")"           # com.selene.prod.<name>.plist
    ex_name="${ex_base#"${DEST_PREFIX}"}"        # <name>.plist
    ex_name="${ex_name%.plist}"                  # <name>
    ex_label="${LABEL_PREFIX}${ex_name}"

    # Still generated this run? Not an orphan.
    if in_array "$ex_name" "${generated_names[@]}"; then
        continue
    fi
    # Protected infra label (e.g. deploy-watcher)? Never touch.
    if in_array "$ex_label" "${RECONCILE_SKIP[@]}"; then
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 || "$NO_LOAD" -eq 1 ]]; then
        echo "[would-prune] orphaned prod plist ${existing} (label ${ex_label})"
        continue
    fi

    echo "pruning orphaned prod plist ${existing} (label ${ex_label})"
    launchctl bootout "gui/${uid}/${ex_label}" 2>/dev/null || true
    rm -f "$existing"
done

# === Pass 2: load ALL generated plists ======================================
# Only on the real load path (not --dry-run, not --no-load). A bootstrap
# failure is reported per-label and does NOT abort the loop (so the user gets a
# full summary); the script exits non-zero at the end if any failed.
if [[ "$DRY_RUN" -eq 0 && "$NO_LOAD" -eq 0 ]]; then
    # C1: launchd does not create the StandardOut/ErrorPath parent dir, so jobs
    # would fail to spawn. Create it before loading.
    mkdir -p "${PROD_DIR}/logs"

    load_failed=()
    for i in "${!generated_labels[@]}"; do
        label="${generated_labels[$i]}"
        dest="${generated_dests[$i]}"
        launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
        if ! launchctl bootstrap "gui/${uid}" "$dest"; then
            echo "ERROR: launchctl bootstrap failed for ${label} (${dest})" >&2
            load_failed+=("$label")
        fi
    done

    if [[ "${#load_failed[@]}" -gt 0 ]]; then
        echo "Load summary: ${#load_failed[@]} of ${#generated_labels[@]} failed to bootstrap:" >&2
        for label in "${load_failed[@]}"; do echo "  - ${label}" >&2; done
        exit 1
    fi
    echo "Loaded ${#generated_labels[@]} plist(s) into gui/${uid}"
fi

# End on a deterministic success status: the script's prior command may be a
# skipped (false) guard whose exit status would otherwise leak out.
exit 0
