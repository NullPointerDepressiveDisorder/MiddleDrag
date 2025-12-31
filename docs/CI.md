# CI/CD Workflow Architecture

This document describes the GitHub Actions CI/CD pipeline structure.

## Overview

```
.github/
├── actions/
│   └── xcodebuild/           # Composite action for build commands
│       └── action.yml
└── workflows/
    ├── BuildAndTest.yml      # PR/push builds + coverage
    ├── codeql.yml            # Security scanning
    ├── close-on-release.yml  # Issue automation
    ├── update-homebrew.yml   # Homebrew tap updates
    ├── release.yml           # Release orchestrator
    ├── _get-version.yml      # Reusable: version detection
    ├── _build-release.yml    # Reusable: build + artifact
    ├── _sentry-upload.yml    # Reusable: Sentry integration
    └── _publish-release.yml  # Reusable: GitHub Release
```

> **Note:** Workflows prefixed with `_` are reusable (called by other workflows, not triggered directly).

## Workflows

### BuildAndTest.yml

- **Triggers:** Push to `main`, PRs
- **Purpose:** Build, run tests, upload coverage to Codecov

### release.yml (Orchestrator)

- **Triggers:** Tag push (`v*`), manual dispatch
- **Pipeline:**
  1. `_get-version.yml` → Resolve/bump version
  2. `_build-release.yml` → Build universal binary
  3. `_sentry-upload.yml` → Upload dSYMs
  4. `_publish-release.yml` → Create GitHub Release + trigger Homebrew

### codeql.yml

- **Triggers:** Push/PR to `main`, weekly schedule
- **Purpose:** Security analysis

### update-homebrew.yml

- **Triggers:** Repository dispatch (from release.yml), manual
- **Purpose:** Update Homebrew cask in the tap repository

### close-on-release.yml

- **Triggers:** Release published
- **Purpose:** Close issues labeled `fixed-pending-release`

## Composite Action

### xcodebuild

Consolidated build command with inputs:

- `scheme`, `project`, `configuration`
- `enable-coverage`, `run-tests`
- `universal-binary`, `derived-data-path`

Used by: `BuildAndTest.yml`, `codeql.yml`, `_build-release.yml`

## Secrets Required

| Secret | Used By |
|--------|---------|
| `CODECOV_TOKEN` | BuildAndTest.yml |
| `SENTRY_AUTH_TOKEN` | _sentry-upload.yml |
| `SENTRY_ORG` | _sentry-upload.yml |
| `SENTRY_PROJECT` | _sentry-upload.yml |
| `HOMEBREW_TAP_TOKEN` | update-homebrew.yml |
| `RELEASER_APP_KEY` | _get-version.yml,_build-release.yml |

## Variables Required

| Variable | Used By |
|----------|---------|
| `RELEASER_APP_ID` | _get-version.yml,_build-release.yml |
