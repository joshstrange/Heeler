#!/bin/sh
# Installs the last device build of Josh's Heeler on his iPhone, waiting for
# the phone when it is not reachable yet.
#
#   install-when-ready.sh --once   try one install now; exit 0 installed, 1 not
#   install-when-ready.sh          retry every $POLL seconds for up to $MAX_WAIT
#                                  seconds, then exit 0 installed, 1 gave up
#
# The phone answers over Wi-Fi while locked, but an install sent to a locked
# phone puts a passcode prompt on its screen, so this waits until the phone is
# reachable and unlocked. Reading the lock state shows nothing on the phone.
# A failed install is retried on the next poll. An install replaces Heeler
# while it runs, so the relaunch brings it straight back. update.sh starts
# the waiting form in the background and stops any older waiter before it
# builds, so a waiter never installs a half-built app. A waiting run posts a Mac notification when it finishes.
set -u
cd "$(dirname "$0")/../.."

DEVICE=${DEVICE:-00008160-000A586102C0000A}   # Josh Strange's iPhone Duo
APP_ID=com.joshstrange.heeler
APP=${APP:-build/DerivedData-device/Build/Products/Debug-iphoneos/Heeler.app}
POLL=${POLL:-60}
MAX_WAIT=${MAX_WAIT:-43200}   # 12 hours
PIDFILE=build/josh-install.pid

say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "install: $*"; }
notify() {
  osascript -e "display notification \"$1\" with title \"Heeler J\"" >/dev/null 2>&1 || true
}

[ -d "$APP" ] || { say "no build at $APP"; exit 1; }

available() {
  xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -Eq 'available|connected'
}

unlocked() {
  xcrun devicectl device info lockState --device "$DEVICE" 2>/dev/null | grep -q 'passcodeRequired: false'
}

try_install() {
  available || return 1
  unlocked || return 1
  xcrun devicectl device install app --device "$DEVICE" "$APP" || return 1
  if xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$APP_ID" >/dev/null 2>&1; then
    say "installed and relaunched"
  else
    say "installed; the relaunch was refused, so Heeler opens fresh next time"
  fi
  return 0
}

if [ "${1:-}" = --once ]; then
  try_install
  exit
fi

echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
say "waiting for $DEVICE to be reachable and unlocked (every ${POLL}s, up to ${MAX_WAIT}s)"
waited=0
while :; do
  if try_install; then
    notify "Installed the latest Heeler on your iPhone."
    exit 0
  fi
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    say "gave up after ${MAX_WAIT}s; run scripts/josh/install-when-ready.sh --once"
    notify "Gave up waiting for your iPhone. Heeler is built but not installed."
    exit 1
  fi
  sleep "$POLL"
  waited=$((waited + POLL))
done
