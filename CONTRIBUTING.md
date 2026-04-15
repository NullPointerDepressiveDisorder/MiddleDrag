# Contributing to MiddleDrag

Thanks for your interest in contributing to MiddleDrag! This project aims to bring reliable middle-click functionality to macOS trackpad users, especially those working with CAD and 3D software.

## Getting Started

### Prerequisites

- macOS 15.0 (Sequoia) or later
- Xcode 16.0 or later
- A trackpad (built-in or Magic Trackpad)

### Setting Up the Development Environment

1. Fork and clone the repository:

   ```bash
   git clone https://github.com/YOUR_USERNAME/MiddleDrag.git
   cd MiddleDrag
   ```

2. Install pre-commit hooks:

   ```bash
   brew install pre-commit
   pre-commit install
   ```

3. Open the project in Xcode:

   ```bash
   open MiddleDrag.xcodeproj
   ```

4. Select your signing team in project settings (for local development, you can use "Sign to Run Locally")

5. Build and run (⌘R)

### Building from Command Line

```bash
# Debug build
./build.sh --debug --run

# Release build
./build.sh
```

## How to Contribute

### Reporting Bugs

Before submitting a bug report:

- Check existing [issues](https://github.com/NullPointerDepressiveDisorder/MiddleDrag/issues) to avoid duplicates
- Include your macOS version and trackpad type
- Describe the expected vs actual behavior
- Include steps to reproduce

### Suggesting Features

Feature requests are welcome! Please:

- Check existing issues first
- Explain the use case and why it would benefit users
- Be specific about the desired behavior

### Pull Requests

1. Fork the repo and create your branch from `main`:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the code style below

3. Test thoroughly — especially gesture recognition and mouse event generation

4. Commit with clear messages:

   ```bash
   git commit -m "Add: description of feature"
   git commit -m "Fix: description of bug fix"
   ```

5. Push and open a Pull Request

### Keeping Your Branch Up to Date

If your PR shows "This branch has conflicts that must be resolved" or has fallen behind `main`, you'll need to update your branch before it can be merged.

**Option 1: Rebase (preferred for clean history)**

```bash
# Add upstream remote if you haven't already (for forks)
git remote add upstream https://github.com/NullPointerDepressiveDisorder/MiddleDrag.git

# Fetch latest changes
git fetch upstream

# Rebase your branch on main
git checkout your-branch-name
git rebase upstream/main

# If there are conflicts, Git will pause and show which files need resolution
# Edit the files to resolve conflicts, then:
git add <resolved-files>
git rebase --continue

# Force push your updated branch (required after rebase)
git push --force-with-lease
```

**Option 2: Merge (simpler but creates merge commits)**

```bash
git fetch upstream
git checkout your-branch-name
git merge upstream/main

# Resolve any conflicts, then:
git add <resolved-files>
git commit
git push
```

**Tips for resolving conflicts:**
- Look for `<<<<<<<`, `=======`, and `>>>>>>>` markers in conflicted files
- The code between `<<<<<<<` and `=======` is your version
- The code between `=======` and `>>>>>>>` is from main
- Edit the file to combine both changes appropriately, then remove all marker lines
- Run `git diff --check` to verify no conflict markers remain

If you're unsure how to resolve a conflict, feel free to ask for help in the PR comments.

## Code Style

### Swift Guidelines

- Use Swift's standard naming conventions (camelCase for variables/functions, PascalCase for types)
- Keep functions focused and reasonably sized
- Add comments for non-obvious logic, especially around the MultitouchSupport framework
- Use `guard` for early returns
- Prefer `let` over `var` where possible

### Project Structure

```
MiddleDrag/
├── Core/           # Gesture detection, mouse events, multitouch API
├── Managers/       # Device monitoring, coordination
├── Models/         # Data structures and configuration
├── UI/             # Menu bar interface, alerts
└── Utilities/      # Preferences, launch-at-login
```

When adding new functionality:

- Place it in the appropriate directory
- Follow the existing patterns for similar code
- Keep the modular architecture intact

### Testing Changes

Since MiddleDrag uses private Apple APIs and requires Accessibility permissions:

1. Test with both built-in and external trackpads if possible
2. Verify gestures work in target apps (browsers, Blender, Fusion 360)
3. Check that system gestures (Mission Control, etc.) still work
4. Test the menu bar UI responds correctly

## Areas Where Help is Appreciated

- **Testing on different hardware**: Various MacBook models, Magic Trackpad generations
- **App compatibility reports**: Which CAD/3D apps work well, which have issues
- **Documentation improvements**: Clearer instructions, translations
- **Bug fixes**: Especially around edge cases in gesture recognition

## Questions?

Feel free to open an issue for questions about the codebase or contribution process.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
