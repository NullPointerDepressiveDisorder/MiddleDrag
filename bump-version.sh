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
sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*/MARKETING_VERSION = $VERSION/g" \
    MiddleDrag.xcodeproj/project.pbxproj

# Validate that MARKETING_VERSION was updated
if ! grep -q "MARKETING_VERSION = $VERSION" MiddleDrag.xcodeproj/project.pbxproj; then
    echo "Error: Failed to update MARKETING_VERSION in project file"
    exit 1
fi
echo "✓ Updated MARKETING_VERSION in Xcode project"

# Stage and commit
git add MiddleDrag.xcodeproj/project.pbxproj
git commit -m "Bump version to $VERSION"
echo "✓ Committed version change"

# Create tag
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "Error: Tag v$VERSION already exists"
    exit 1
fi

git tag "v$VERSION"
echo "✓ Created tag v$VERSION"

echo ""
echo "Done! To trigger the release workflow, run:"
echo "  git push && git push --tags"
