#!/bin/bash
# bump-version.sh - Update version in Xcode project and create git tag

set -e

VERSION=$1
NOTES=$2

if [ -z "$VERSION" ]; then
    echo "Usage: ./bump-version.sh <version> [notes]"
    echo "Example: ./bump-version.sh 1.2.3 \"Release notes\""
    exit 1
fi

# Remove 'v' prefix if provided
VERSION="${VERSION#v}"

# Validate semver format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in semver format (e.g., 1.2.3)"
    exit 1
fi

# Ensure working directory is clean (only allow staged changes, not unstaged)
if ! git diff --quiet; then
    echo "Error: Working directory has unstaged changes. Please commit or stash them first."
    exit 1
fi
echo "Bumping version to $VERSION..."

# Update Xcode project MARKETING_VERSION (both Debug and Release configs)
if [ ! -f "MiddleDrag.xcodeproj/project.pbxproj" ]; then
    echo "Error: MiddleDrag.xcodeproj/project.pbxproj not found. Are you in the project root?"
    exit 1
fi
sed -i '' -E "s/MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+/MARKETING_VERSION = $VERSION/g" \
    MiddleDrag.xcodeproj/project.pbxproj

# Verify exactly 2 instances were updated
COUNT=$(grep -c "MARKETING_VERSION = $VERSION" MiddleDrag.xcodeproj/project.pbxproj || echo "0")
if [ "$COUNT" -ne 2 ]; then
    echo "Error: Expected exactly 2 MARKETING_VERSION updates, found $COUNT"
    exit 1
fi
echo "✓ Updated MARKETING_VERSION in Xcode project"

# Check if tag already exists (local or remote)
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "Error: Tag v$VERSION already exists locally"
    exit 1
fi
if git ls-remote --tags origin | grep -q "refs/tags/v$VERSION$"; then
    echo "Error: Tag v$VERSION already exists on remote"
    exit 1
fi

# Stage and amend previous commit
echo "⚠️  Warning: This will amend the last commit. Make sure it hasn't been pushed yet."
read -p "Continue (y/n) " -n 1 -r 
echo
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi
git add MiddleDrag.xcodeproj/project.pbxproj
git commit --amend --no-edit
echo "✓ Amended previous commit with version change"

# Create tag
if [ -n "$NOTES" ]; then
    git tag -a "v$VERSION" --message="$NOTES"
    echo "✓ Created annotated tag v$VERSION"
else
    git tag "v$VERSION"
    echo "✓ Created tag v$VERSION"
fi
echo ""
echo "Done! To trigger the release workflow, run:"
echo "  git push && git push --tags"
