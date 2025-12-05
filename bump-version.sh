#!/bin/bash
# bump-version.sh - Update version in Xcode project and create git tag

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./bump-version.sh <version>"
    echo "Example: ./bump-version.sh 1.2.3"
    exit 1
fi

# Remove 'v' prefix if provided
VERSION="${VERSION#v}"

# Validate semver format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must be in semver format (e.g., 1.2.3)"
    exit 1
fi

# Ensure working directory is clean
if ! git diff-index --quiet HEAD --; then
    echo "Error: Working directory has uncommitted changes. Please commit or stash them first."
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

# Validate that MARKETING_VERSION was updated (should have 2 instances: Debug and Release)
COUNT=$(grep -c "MARKETING_VERSION = $VERSION" MiddleDrag.xcodeproj/project.pbxproj || true)
if [ "$COUNT" -eq 0 ]; then
    echo "Error: Failed to update MARKETING_VERSION in project file"
    exit 1
elif [ "$COUNT" -lt 2 ]; then
    echo "Warning: Only $COUNT instance(s) of MARKETING_VERSION updated (expected 2)"
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

# Stage and commit
git add MiddleDrag.xcodeproj/project.pbxproj
git commit -m "Bump version to $VERSION"
echo "✓ Committed version change"

# Create tag
git tag "v$VERSION"
echo "✓ Created tag v$VERSION"
echo ""
echo "Done! To trigger the release workflow, run:"
echo "  git push && git push --tags"
