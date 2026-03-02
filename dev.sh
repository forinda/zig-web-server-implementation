#!/usr/bin/env bash
#
# dev.sh - Hot reload for the Zig web server
# Usage: ./dev.sh [port]
#
# Watches src/ for .zig file changes and automatically rebuilds & restarts.
# Uses inotifywait if available (instant), otherwise polls every 1s.

set -euo pipefail

# ---- Configuration (reads the same env vars as the app) ----
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG="${ZIG:-/home/forinda/sdk/zig/zig}"
WATCH_DIR="${PROJECT_DIR}/src"
BUILD_CMD="${ZIG} build"
BINARY="${PROJECT_DIR}/zig-out/bin/server"
POLL_INTERVAL=1

export PORT="${PORT:-8080}"
export DB_NAME="${DB_NAME:-data.db}"
export APP_NAME="${APP_NAME:-Zig Web Server}"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- State ----
SERVER_PID=""

# ---- Helpers ----
timestamp() {
    date '+%H:%M:%S'
}

log_info() {
    echo -e "${CYAN}[$(timestamp)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(timestamp)]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(timestamp)]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(timestamp)]${NC} $1"
}

# ---- Process Management ----
kill_server() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stopping server (PID $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
}

start_server() {
    if [ ! -f "$BINARY" ]; then
        log_error "Binary not found at $BINARY"
        return 1
    fi
    "$BINARY" &
    SERVER_PID=$!
    log_success "Server started (PID $SERVER_PID)"
}

build_server() {
    log_info "Building..."
    if $BUILD_CMD 2>&1; then
        log_success "Build succeeded"
        return 0
    else
        log_error "Build FAILED"
        return 1
    fi
}

reload() {
    local changed_file="${1:-}"
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    if [ -n "$changed_file" ]; then
        log_warn "Change detected: ${changed_file}"
    else
        log_warn "Change detected"
    fi
    echo -e "${YELLOW}========================================${NC}"

    kill_server

    if build_server; then
        start_server
    else
        log_error "Server not restarted due to build failure."
        log_info "Fix the error and save again to retry."
    fi
}

# ---- Cleanup on exit ----
cleanup() {
    echo ""
    log_info "Shutting down dev server..."
    kill_server
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# ---- Watch Strategies ----

watch_inotify() {
    log_info "Using inotifywait (event-driven)"
    while true; do
        changed=$(inotifywait -r -q -e modify,create,delete,move \
            --include '\.zig$' \
            --format '%w%f' \
            "$WATCH_DIR" 2>/dev/null) || true

        if [ -n "$changed" ]; then
            # Debounce: drain events that arrive within 200ms
            sleep 0.2
            inotifywait -r -q -t 0 -e modify,create,delete,move \
                --include '\.zig$' \
                "$WATCH_DIR" >/dev/null 2>&1 || true

            reload "$changed"
        fi
    done
}

watch_poll() {
    log_info "Using polling (${POLL_INTERVAL}s interval)"
    log_info "(Install inotify-tools for instant reload: sudo apt install inotify-tools)"

    local marker
    marker=$(mktemp)
    touch "$marker"

    trap "rm -f '$marker'; cleanup" SIGINT SIGTERM EXIT

    while true; do
        sleep "$POLL_INTERVAL"

        local changed
        changed=$(find "$WATCH_DIR" -name '*.zig' -newer "$marker" -print -quit 2>/dev/null)

        if [ -n "$changed" ]; then
            touch "$marker"
            reload "$changed"
        fi
    done
}

# ---- Main ----
echo -e "${CYAN}"
echo "  ========================================="
echo "    ${APP_NAME} - Hot Reload Mode"
echo "  ========================================="
echo -e "${NC}"
log_info "Watching: ${WATCH_DIR}"
log_info "Binary:   ${BINARY}"
log_info "Zig:      ${ZIG} ($(${ZIG} version 2>/dev/null || echo 'unknown'))"
log_info "Port:     ${PORT}"
log_info "Database: ${DB_NAME}"
echo ""

# Initial build and start
if build_server; then
    start_server
else
    log_error "Initial build failed. Fix errors and save a .zig file to retry."
fi

# Choose watch strategy
if command -v inotifywait &>/dev/null; then
    watch_inotify
else
    watch_poll
fi
