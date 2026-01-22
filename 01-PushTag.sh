#!/usr/bin/env bash
set -e

REMOTE="origin"
TODO_FILE="/home/e/AndroidStudioProjects/memorizer/lib/ToDo.txt"

# ===== dry-run switch =====
#DRY="--dry-run"
DRY=""
# ==========================

echo "=== Checking that the working tree is clean ==="

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: You have uncommitted changes."
    echo "Please commit or stash them before running this script."
    exit 1
fi

echo "OK: Working tree is clean."

echo "=== Detecting latest tag ==="
LAST_TAG=$(git tag --list 'v*' | sort -V | tail -n 1)

if [[ -z "$LAST_TAG" ]]; then
    echo "ERROR: No tags found."
    exit 1
fi

NOW=$(date "+%F %H:%M:%S")   # YYYY-MM-DD HH:MM:SS
TAG_LINE="# $LAST_TAG ($NOW)"

echo "Latest tag: $LAST_TAG"
echo "Tag line: $TAG_LINE"

echo "=== Updating $TODO_FILE ==="

if [[ ! -f "$TODO_FILE" ]]; then
    echo "ERROR: File $TODO_FILE not found."
    exit 1
fi

TMP_FILE="$(mktemp)"

awk -v tag="$TAG_LINE" '
/^===TODO:/ || /^===TOFIX:/ || /^===ERRORS:/ {
    print $0
    getline nextline

    # Do not duplicate the tag if it already exists
    if (nextline != tag) {
        print tag
    }
    print nextline
    next
}
{
    print
}
' "$TODO_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$TODO_FILE"

# Check if there are any changes
if git diff --quiet; then
    echo "No changes in $TODO_FILE (tag already exists)."
else
    echo "=== Committing todo update ==="
    git add "$TODO_FILE"
    git commit -m "Update todo for $LAST_TAG ($NOW)"
fi

echo "=== Pushing current branch ($DRY) ==="
git push $DRY "$REMOTE"

echo "=== Pushing tag ($DRY) ==="
git push $DRY "$REMOTE" "$LAST_TAG"

echo "=== Done ==="
