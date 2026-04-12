#!/usr/bin/env bash
# Bumps the version in pubspec.yaml.
#
# Version format: X.Y.Z+N
#   X.Y.Z = semantic version name (shown to users)
#   N     = build number (must strictly increase for every Apple upload)
#
# The build number is ALWAYS incremented, regardless of which semantic
# bump you pick. That's what Apple wants.
#
# Usage:
#   ./scripts/bump-version.sh             # patch bump (default): 1.0.1+2 → 1.0.2+3
#   ./scripts/bump-version.sh patch       # 1.0.1+2 → 1.0.2+3
#   ./scripts/bump-version.sh minor       # 1.0.1+2 → 1.1.0+3
#   ./scripts/bump-version.sh major       # 1.0.1+2 → 2.0.0+3
#   ./scripts/bump-version.sh build       # build-only: 1.0.1+2 → 1.0.1+3

set -e

cd "$(dirname "$0")/.."

PUBSPEC="pubspec.yaml"
[[ -f "$PUBSPEC" ]] || { echo "pubspec.yaml not found in $(pwd)"; exit 1; }

BUMP="${1:-patch}"

# Grab the current "version: X.Y.Z+N" line
CURRENT="$(awk '/^version: / {print $2; exit}' "$PUBSPEC")"
[[ -n "$CURRENT" ]] || { echo "No 'version:' line in pubspec.yaml"; exit 1; }

# Split name from build number
NAME="${CURRENT%+*}"
BUILD="${CURRENT##*+}"

# Split semver
IFS='.' read -r MAJOR MINOR PATCH <<< "$NAME"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  build) ;;  # semantic version untouched
  *)
    echo "Unknown bump: '$BUMP'"
    echo "Use one of: major | minor | patch | build"
    exit 1
    ;;
esac

# Always bump the build number
BUILD=$((BUILD + 1))
NEW="${MAJOR}.${MINOR}.${PATCH}+${BUILD}"

# Portable in-place rewrite (works on BSD sed/macOS)
tmp="$(mktemp)"
awk -v new="version: $NEW" '
  /^version: / { print new; next }
  { print }
' "$PUBSPEC" > "$tmp" && mv "$tmp" "$PUBSPEC"

echo "✅ $CURRENT → $NEW"
echo ""
echo "Next steps:"
echo "  flutter pub get"
echo "  ./run.sh --install --fast"
