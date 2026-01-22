#!/usr/bin/env bash
set -e

PROJECT="memorizer"
APK_DIR="/home/e/AndroidStudioProjects/memorizer/build/app/outputs/flutter-apk"
TODO_FILE="lib/ToDo.txt"
CHANGELOG_FILE="/tmp/release_notes_$$.md"

echo "=== Detecting latest tag ==="
TAG=$(git tag --list 'v*' | sort -V | tail -n 1)

if [[ -z "$TAG" ]]; then
    echo "ERROR: No tags found."
    exit 1
fi

echo "Tag: $TAG"

# ------------------------------------------------------------
# Parse tag: v0.7.260115+26  ->  VERSION=0.7.260115  BUILD=26
# ------------------------------------------------------------
CLEAN_TAG="${TAG#v}"
VERSION="${CLEAN_TAG%%+*}"
BUILD="${CLEAN_TAG##*+}"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    echo "ERROR: Failed to parse tag: $TAG"
    exit 1
fi

echo "Version: $VERSION"
echo "Build:   $BUILD"

# ------------------------------------------------------------
# Function: build_changelog
# Stops at ANY version tag (# v...) after current tag
# ------------------------------------------------------------
build_changelog() {
    local todo_file="$1"
    local cur_tag="$2"
    local out_file="$3"

    awk -v cur="# $cur_tag" '
    BEGIN {
        group=""
        capture=0
        printed["TODO"]=0
        printed["TOFIX"]=0
        printed["ERRORS"]=0
    }

    # Detect group headers
    /^===TODO:/   { group="TODO";   capture=0; next }
    /^===TOFIX:/  { group="TOFIX";  capture=0; next }
    /^===ERRORS:/ { group="ERRORS"; capture=0; next }

    # Start capture after current tag inside group
    group != "" && index($0, cur) == 1 {
        capture=1
        next
    }

    # Stop capture at any other version tag (# v...)
    group != "" && capture && /^# v[0-9]/ {
        capture=0
        next
    }

    # Capture items
    capture && /^[+]/ {
        # Print group header once
        if (!printed[group]) {
            print ""
            print "### From " group ":"
            printed[group]=1
        }

        sub(/^[+][[:space:]]*/, "- ")
        print
        next
    }
    ' "$todo_file" > "$out_file"
}

# ------------------------------------------------------------
# Build changelog
# ------------------------------------------------------------
echo "=== Building changelog from $TODO_FILE ==="
build_changelog "$TODO_FILE" "$TAG" "$CHANGELOG_FILE"

echo "Generated changelog:"
echo "--------------------------------------------------"
cat "$CHANGELOG_FILE"
echo "--------------------------------------------------"

# ------------------------------------------------------------
# Real APK file names on disk (app-*)
# ------------------------------------------------------------
SRC_APK_MAIN="app-release-${VERSION}-${BUILD}.apk"
SRC_APK_ARM64="app-arm64-v8a-release-${VERSION}-${BUILD}.apk"

# ------------------------------------------------------------
# SHA256 files we will generate locally
# ------------------------------------------------------------
SRC_SHA_MAIN="app-release.apk.sha256"
SRC_SHA_ARM64="app-arm64-v8a-release.apk.sha256"

# ------------------------------------------------------------
# Target file names in GitHub Release (memorizer-*)
# ------------------------------------------------------------
DST_APK_MAIN="${PROJECT}-release-${VERSION}-${BUILD}.apk"
DST_SHA_MAIN="${PROJECT}-release.apk.sha256"

DST_APK_ARM64="${PROJECT}-arm64-v8a-release-${VERSION}-${BUILD}.apk"
DST_SHA_ARM64="${PROJECT}-arm64-v8a-release.apk.sha256"

# ------------------------------------------------------------
# Check APK existence
# ------------------------------------------------------------
echo "=== Checking APK files in $APK_DIR ==="

for f in "$SRC_APK_MAIN" "$SRC_APK_ARM64"; do
    if [[ ! -f "$APK_DIR/$f" ]]; then
        echo "ERROR: File not found: $APK_DIR/$f"
        exit 1
    fi
    echo "OK: $f"
done

# ------------------------------------------------------------
# Generate SHA256
# ------------------------------------------------------------
echo "=== Generating SHA256 checksums ==="

(
    cd "$APK_DIR"

    echo "Generating $SRC_SHA_MAIN"
    sha256sum "$SRC_APK_MAIN" > "$SRC_SHA_MAIN"

    echo "Generating $SRC_SHA_ARM64"
    sha256sum "$SRC_APK_ARM64" > "$SRC_SHA_ARM64"
)

# ------------------------------------------------------------
# Files to upload (source#destination)
# ------------------------------------------------------------
FILES=(
    "$SRC_APK_MAIN#$DST_APK_MAIN"
    "$SRC_SHA_MAIN#$DST_SHA_MAIN"
    "$SRC_APK_ARM64#$DST_APK_ARM64"
    "$SRC_SHA_ARM64#$DST_SHA_ARM64"
)

echo "=== Verifying generated files ==="

for pair in "${FILES[@]}"; do
    SRC="${pair%%#*}"
    if [[ ! -f "$APK_DIR/$SRC" ]]; then
        echo "ERROR: File not found: $APK_DIR/$SRC"
        exit 1
    fi
    echo "OK: $SRC"
done

# ------------------------------------------------------------
# Create release if not exists
# ------------------------------------------------------------
echo "=== Checking if GitHub Release exists ==="

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release already exists."
else
    echo "Creating GitHub Release..."
    gh release create "$TAG" \
        --title "Release $TAG" \
        --notes-file "$CHANGELOG_FILE"
fi

# ------------------------------------------------------------
# Upload files with renaming
# ------------------------------------------------------------
echo "=== Uploading files to Release ==="

for pair in "${FILES[@]}"; do
    SRC="${pair%%#*}"
    DST="${pair##*#}"
    echo "Uploading: $SRC -> $DST"
    gh release upload "$TAG" "$APK_DIR/$pair" --clobber
done

echo "=== Release upload completed successfully ==="

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------
rm -f "$CHANGELOG_FILE"
