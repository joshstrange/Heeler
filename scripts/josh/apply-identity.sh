#!/bin/sh
# Re-brand this checkout to Josh's own App ID so it can be signed by the
# GrubBux LLC team and installed beside the official TestFlight app.
# Idempotent: safe to re-run after a rebase that took upstream's version of a
# file. Only identifiers Apple ties to a team are changed; keychain service
# names, logger subsystems and task identifiers stay as upstream has them.
set -eu
cd "$(dirname "$0")/../.."

TEAM=6TVZ6QN944                      # GrubBux LLC
OLD=dev.bybee.heeler
NEW=com.joshstrange.heeler
NAME="Heeler J"                      # home-screen name, to tell it from TestFlight's

# project.yml: team, bundle IDs, app group, display name.
sed -i '' \
  -e "s/DEVELOPMENT_TEAM: 9VM4RM39R3/DEVELOPMENT_TEAM: $TEAM/" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER: $OLD/PRODUCT_BUNDLE_IDENTIFIER: $NEW/" \
  -e "s/group\.$OLD\.shared/group.$NEW.shared/" \
  -e "s/INFOPLIST_KEY_CFBundleDisplayName: Heeler\$/INFOPLIST_KEY_CFBundleDisplayName: $NAME/" \
  project.yml

# Entitlements (XcodeGen also rewrites these from project.yml) and the one
# Swift constant that names the app group.
for f in Sources/Heeler/Heeler.entitlements \
         Sources/HeelerNotificationService/HeelerNotificationService.entitlements \
         Sources/HeelerWidgets/HeelerWidgets.entitlements \
         Sources/HeelerNotificationCore/NotificationKeyStore.swift; do
  sed -i '' "s/group\.$OLD\.shared/group.$NEW.shared/" "$f"
done

# Fail loudly if upstream moved something this script expects to change.
left=$(grep -nE "9VM4RM39R3|PRODUCT_BUNDLE_IDENTIFIER: $OLD|group\.$OLD" project.yml \
  Sources/*/*.entitlements Sources/HeelerNotificationCore/NotificationKeyStore.swift || true)
if [ -n "$left" ]; then
  echo "apply-identity: still names the upstream identity:" >&2
  echo "$left" >&2
  exit 1
fi
grep -q "CFBundleDisplayName: $NAME" project.yml || { echo "apply-identity: display name not set" >&2; exit 1; }
echo "apply-identity: $NEW on team $TEAM"
