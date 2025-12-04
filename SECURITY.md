# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in MiddleDrag, please report it through GitHub's Security Advisory feature:

1. Go to the [Security tab](https://github.com/nullpointerdepressivedisorder/MiddleDrag/security)
2. Click "Report a vulnerability"
3. Fill out the private form

**Do NOT open a public GitHub issue for security vulnerabilities.**

Include the following in your report:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

### What to expect

- **Acknowledgment**: Within 48 hours of your report
- **Initial assessment**: Within 7 days
- **Resolution timeline**: Depends on severity, typically 30-90 days
- **Credit**: We'll credit you in the release notes (unless you prefer to remain anonymous)

## Security Considerations

MiddleDrag requires the following system permissions:

- **Accessibility**: Required to simulate mouse events. The app cannot function without this permission.

### What MiddleDrag does NOT do

- Does not collect personal information
- Does not transmit sensitive data (analytics are opt-out and privacy-focused)
- Does not modify system files
- Does not run background processes when disabled

### Code Signing

Release builds are signed with an ad-hoc signature. Users may need to grant permissions in System Settings after installation.

## Dependencies

We monitor dependencies for known vulnerabilities. Current dependencies:
- [Sentry](https://github.com/getsentry/sentry-cocoa) - Crash reporting
- [SimpleAnalytics](https://github.com/simpleanalytics/swift-package) - Anonymous usage analytics
