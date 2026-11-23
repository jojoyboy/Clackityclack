#!/bin/bash
set -e

VERSION="${1}"
NOTES="${2:-"Clackity release update"}"

if [ -z "$VERSION" ]; then
    echo "Usage: ./tools/publish_release.sh <version_tag> [release_notes]"
    echo "Example: ./tools/publish_release.sh v1.0.1 'Added new switch sounds'"
    exit 1
fi

echo "==> Building fresh Clackity distribution (pkg + zip)..."
make dist

echo "==> Tagging git commit with $VERSION..."
git tag "$VERSION"
git push origin "$VERSION"

echo "==> Creating GitHub Release $VERSION..."
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain get | grep '^password=' | cut -d= -f2)

RELEASE_JSON=$(curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -d "{\"tag_name\":\"$VERSION\",\"name\":\"Clackity $VERSION\",\"body\":\"$NOTES\",\"draft\":false,\"prerelease\":false}" \
  https://api.github.com/repos/jojoyboy/Clackityclack/releases)

RELEASE_ID=$(echo "$RELEASE_JSON" | grep -m 1 '"id":' | awk '{print $2}' | tr -d ',')

echo "==> Uploading Clackity-Installer.pkg to Release ID: $RELEASE_ID..."
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @build.noindex/Clackity-Installer.pkg \
  "https://uploads.github.com/repos/jojoyboy/Clackityclack/releases/$RELEASE_ID/assets?name=Clackity-Installer.pkg" > /dev/null

echo "==> Uploading Clackity-macOS.zip to Release ID: $RELEASE_ID..."
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/zip" \
  --data-binary @build.noindex/Clackity-macOS.zip \
  "https://uploads.github.com/repos/jojoyboy/Clackityclack/releases/$RELEASE_ID/assets?name=Clackity-macOS.zip" > /dev/null

echo "==> Release $VERSION published successfully!"
echo "==> Direct download URL (pkg): https://github.com/jojoyboy/Clackityclack/releases/download/$VERSION/Clackity-Installer.pkg"
echo "==> Direct download URL (zip): https://github.com/jojoyboy/Clackityclack/releases/download/$VERSION/Clackity-macOS.zip"
