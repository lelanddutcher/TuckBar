#!/usr/bin/env bash
# End-to-end: run the real app against a virtual second display and assert what it does.
# Needs a logged-in macOS GUI session with Accessibility / Apple Events granted to the shell
# (GitHub-hosted macOS runners have this). Not for a developer machine: it changes the
# menu-bar auto-hide setting and TuckBar's preferences, and restores both at the end.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$ROOT/Lab/.build/release/Lab"
APP="$ROOT/build/TuckBar.app/Contents/MacOS/TuckBar"
DOMAIN=com.lelanddutcher.TuckBar
OUT="$ROOT/e2e-out"; mkdir -p "$OUT"
FAIL=0

lab() { "$LAB" "$@" | grep '^LAB ' | tee -a "$OUT/e2e.log"; }
json() { sed 's/^LAB [a-z.]* //'; }
check() { # name, python expression over `d` (the inspect JSON)
  local name="$1" expr="$2" line="$3"
  if echo "$line" | json | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if ($expr) else 1)"; then
    echo "PASS $name" | tee -a "$OUT/e2e.log"
  else
    echo "FAIL $name" | tee -a "$OUT/e2e.log"; FAIL=1
  fi
}
cleanup() {
  [ -n "${APP_PID:-}" ] && kill "$APP_PID" 2>/dev/null
  [ -n "${VD_PID:-}" ] && kill "$VD_PID" 2>/dev/null
  osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to false' >/dev/null 2>&1
  defaults delete "$DOMAIN" >/dev/null 2>&1
}
trap cleanup EXIT

# 1. A second display.
"$LAB" vhold 1440 900 > "$OUT/vd.log" 2>&1 &
VD_PID=$!
for _ in $(seq 1 40); do grep -q '^LAB vdisplay ' "$OUT/vd.log" && break; grep -q 'vdisplay.fail' "$OUT/vd.log" && break; sleep 0.5; done
cat "$OUT/vd.log"
VD_UUID=$(grep '^LAB vdisplay ' "$OUT/vd.log" | json | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])' 2>/dev/null)
if [ -z "$VD_UUID" ]; then echo "FAIL virtual display could not be created"; exit 1; fi
sleep 2

start_app() { # extra defaults are already written by the caller
  "$APP" > "$OUT/app-$1.log" 2>&1 &
  APP_PID=$!
  sleep 6
}
stop_app() { kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null; APP_PID=""; sleep 3; }

# 2. Default mode: cover over the tagged (virtual) display only; native auto-hide off.
defaults delete "$DOMAIN" >/dev/null 2>&1
defaults write "$DOMAIN" autoProtectEnabled -bool true
defaults write "$DOMAIN" protectedDisplayIDs -array "$VD_UUID"
defaults write "$DOMAIN" coverUsesWallpaper -bool false
start_app cover
L=$(lab inspect cover)
check "two displays present, one of them the tagged virtual display" \
  "len(d['screens'])==2 and any(s['uuid']=='$VD_UUID' for s in d['screens'])" "$L"
check "cover: a TuckBar window covers the tagged display's strip" \
  "any(w['onscreen'] and w['layer']>=25 and w['bounds']['h']<=60 and any(abs(w['bounds']['x']-s['frame']['x'])<1 and abs(w['bounds']['w']-s['frame']['w'])<1 for s in d['screens'] if s['uuid']=='$VD_UUID') for w in d['tuckbar'])" "$L"
check "cover: the untagged display has no cover" \
  "not any(w['onscreen'] and w['layer']>=25 and w['bounds']['h']<=60 and any(abs(w['bounds']['x']-s['frame']['x'])<1 for s in d['screens'] if s['uuid']!='$VD_UUID') for w in d['tuckbar'])" "$L"
check "cover: native auto-hide stays off" "d['autohide']['systemEvents']=='false'" "$L"
check "cover: every display still reserves its bar" "all(s['topInset']>1 for s in d['screens'])" "$L"
stop_app

# 3. "Use the full screen": native auto-hide, no cover, strip free on every display.
defaults write "$DOMAIN" useFullScreenWhenTucked -bool true
start_app fullscreen
L=$(lab inspect fullscreen)
check "full screen: native auto-hide is on" "d['autohide']['systemEvents']=='true'" "$L"
check "full screen: no cover window" "not any(w['onscreen'] and w['layer']>=25 for w in d['tuckbar'])" "$L"
check "full screen: the strip is free on the tagged display" "any(s['uuid']=='$VD_UUID' and s['topInset']<=1 for s in d['screens'])" "$L"
stop_app

# 4. Quitting (SIGTERM, as stop_app sends) restored the bar.
L=$(lab inspect after-quit)
check "after quit: auto-hide restored" "d['autohide']['systemEvents']=='false'" "$L"
check "after quit: strip reserved again" "all(s['topInset']>1 for s in d['screens'])" "$L"

exit $FAIL
