#!/bin/sh
# Weekly upstream sync for Josh's Heeler fork.
#   1. fetch ZingerLittleBee/Heeler, mirror its main to origin/main
#   2. rebase the `josh` branch onto it (identity-file conflicts resolve
#      themselves by taking upstream's file and re-running apply-identity.sh)
#   3. build, and install on the iPhone when it is reachable
#   4. push `josh` to origin
# Exit codes: 0 done or already current, 2 needs a human (dirty tree, a
# conflict outside the identity files, or a failed build).
set -eu
cd "$(dirname "$0")/../.."

DEVICE=${DEVICE:-00008150-00120CD12E88401C}   # Josh Strange's iPhone (2), iPhone 17 Pro Max
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
if xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -q 'available'; then
  say "building and installing on $DEVICE (log: $LOG)"
  make install DEVICE="$DEVICE" APP_ID="$APP_ID" >"$LOG" 2>&1 || { tail -30 "$LOG"; stop "build or install failed"; }
  installed=yes
else
  say "iPhone not reachable; build only (log: $LOG)"
  make generate >"$LOG" 2>&1
  xcodebuild -project Heeler.xcodeproj -scheme Heeler -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData-device \
    -allowProvisioningUpdates build >>"$LOG" 2>&1 || { tail -30 "$LOG"; stop "build failed"; }
  installed=no
fi
git checkout -q -- Heeler.xcodeproj 2>/dev/null || true

git push -q --force-with-lease origin josh
say "done: josh is upstream $(git rev-parse --short "$new_base") + $(git rev-list --count upstream/main..josh) commit(s); installed=$installed"
