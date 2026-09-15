#!/usr/bin/env bash
# Harmonia build/check script.
# There is nothing to compile — Harmonia is pure Python with no pip
# dependencies — so "build" means: verify the runtime environment, byte-
# compile every module, and run the test suite.
set -euo pipefail
cd "$(dirname "$0")"

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
ok(){ echo "${GREEN}ok${OFF}   $*"; }
warn(){ echo "${YELLOW}warn${OFF} $*"; }
fail(){ echo "${RED}FAIL${OFF} $*"; exit 1; }

echo "== Checking runtime requirements =="

python3 - <<'PY' || exit 1
import sys
if sys.version_info < (3, 10):
    sys.exit(f"Python 3.10+ required, found {sys.version.split()[0]}")
print(f"Python {sys.version.split()[0]}")
PY
ok "Python version"

command -v ffmpeg  >/dev/null || fail "ffmpeg not found — required for audio decoding (pacman -S ffmpeg)"
command -v ffprobe >/dev/null || fail "ffprobe not found — ships with ffmpeg"
ok "ffmpeg $(ffmpeg -version | head -1 | cut -d' ' -f3)"

python3 - <<'PY' || fail "SQLite lacks FTS5 — library search needs it"
import sqlite3
sqlite3.connect(":memory:").execute("CREATE VIRTUAL TABLE t USING fts5(a)")
PY
ok "SQLite FTS5"

python3 - <<'PY' && ok "ALSA (libasound) loadable" || warn "libasound not loadable — playback will be silent"
import ctypes, ctypes.util, sys
name = ctypes.util.find_library("asound") or "libasound.so.2"
try: ctypes.CDLL(name)
except OSError: sys.exit(1)
PY

python3 -c "import numpy" 2>/dev/null \
  && ok "numpy (fast volume/ReplayGain scaling)" \
  || warn "numpy missing — falls back to stdlib audioop (slower but works)"

python3 -c "import dbus_next" 2>/dev/null \
  && ok "dbus-next (MPRIS/media keys)" \
  || warn "dbus-next missing — MPRIS, media keys and playerctl will be disabled"

echo
echo "== Byte-compiling =="
python3 -m compileall -q src gtk_skeleton tests >/dev/null || fail "byte-compilation failed"
ok "all modules compile"

echo
echo "== Running test suite =="
./scripts/test.sh

echo
echo "${GREEN}Build complete.${OFF} Start the player with:  ./scripts/run.sh"
