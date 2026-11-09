#!/bin/sh
# Daily upstream sync for Josh's Heeler fork.
#   1. fetch ZingerLittleBee/Heeler, mirror its main to origin/main
#   2. rebase the `josh` branch onto it (identity-file conflicts resolve
#      themselves by taking upstream's file and re-running apply-identity.sh)
#   3. build, and install on the iPhone; when it is not reachable, leave
#      install-when-ready.sh waiting for it in the background
#   4. push `josh` to origin
# Exit codes: 0 done or already current, 2 needs a human (dirty tree, a
# conflict outside the identity files, or a failed build).
set -eu
cd "$(dirname "$0")/../.."

DEVICE=${DEVICE:-00008160-000A586102C0000A}   # Josh Strange's iPhone Duo
APP_ID=com.joshstrange.heeler
LOG=${LOG:-build/josh-update.log}
IDENTITY_FILES="project.yml Sources/Heeler/Heeler.entitlements
Sources/HeelerNotificationService/HeelerNotificationService.entitlements
Sources/HeelerWidgets/HeelerWidgets.entitlements
Sources/HeelerNotificationCore/NotificationKeyStore.swift
Sources/Heeler/Notifications/NotificationRelayEndpoint.swift"

say() { printf '%s\n' "update: $*"; }
stop() { say "$*"; exit 2; }

[ "$(git branch --show-current)" = josh ] || stop "not on the josh branch"

# XcodeGen rewrites the committed project on every make target; that output
# is never ours to keep.
git checkout -q -- Heeler.xcodeproj 2>/dev/null || true
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git status --short
  stop "uncommitted changes; commit or stash them first"
fi

git fetch -q upstream
old_base=$(git merge-base josh upstream/main)
new_base=$(git rev-parse upstream/main)
git push -q origin upstream/main:refs/heads/main || say "could not mirror upstream main to origin (continuing)"

if [ "$old_base" = "$new_base" ] && [ "${FORCE_BUILD:-0}" != 1 ]; then
  say "already on upstream $(git rev-parse --short "$new_base"); nothing to do"
  exit 0
fi

say "upstream $(git rev-parse --short "$old_base")..$(git rev-parse --short "$new_base"): $(git rev-list --count "$old_base..$new_base") commits"

if ! git rebase -q upstream/main; then
  while :; do
    conflicted=$(git diff --name-only --diff-filter=U)
    [ -n "$conflicted" ] || break
    for f in $conflicted; do
      case " $(echo $IDENTITY_FILES) " in
        *" $f "*) git checkout -q --ours -- "$f" ;;   # in a rebase, --ours is upstream
        *) git rebase --abort; stop "conflict outside the identity files: $f" ;;
      esac
    done
    scripts/josh/apply-identity.sh
    git add -- $IDENTITY_FILES
    GIT_EDITOR=true git rebase --continue || continue
  done
  if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
    git rebase --abort; stop "rebase stopped for a reason other than a conflict"
  fi
fi
scripts/josh/apply-identity.sh
if [ -n "$(git status --porcelain --untracked-files=no -- $IDENTITY_FILES)" ]; then
  stop "apply-identity changed files after the rebase; review and commit them"
fi

mkdir -p build
INSTALL_LOG=build/josh-install.log
# An older waiter must not install the app this run is about to rebuild.
if [ -f build/josh-install.pid ]; then
  pid=$(cat build/josh-install.pid)
  if ps -p "$pid" -o command= 2>/dev/null | grep -q install-when-ready; then
    kill "$pid" && say "stopped an older install waiter"
  fi
  rm -f build/josh-install.pid
fi
if xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -Eq 'available|connected'; then
  say "building for $DEVICE (log: $LOG)"
  make build-device DEVICE="$DEVICE" >"$LOG" 2>&1 || { tail -30 "$LOG"; stop "build failed"; }
else
  say "iPhone not reachable; generic device build (log: $LOG)"
  make generate >"$LOG" 2>&1
  xcodebuild -project Heeler.xcodeproj -scheme Heeler -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData-device \
    -allowProvisioningUpdates build >>"$LOG" 2>&1 || { tail -30 "$LOG"; stop "build failed"; }
fi
if DEVICE="$DEVICE" scripts/josh/install-when-ready.sh --once >>"$LOG" 2>&1; then
  installed=yes
else
  DEVICE="$DEVICE" nohup scripts/josh/install-when-ready.sh >>"$INSTALL_LOG" 2>&1 </dev/null &
  installed="waiting for the iPhone in the background (log: $INSTALL_LOG)"
fi
git checkout -q -- Heeler.xcodeproj 2>/dev/null || true

git push -q --force-with-lease origin josh
say "done: josh is upstream $(git rev-parse --short "$new_base") + $(git rev-list --count upstream/main..josh) commit(s); installed=$installed"
