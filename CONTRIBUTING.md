# Contributing to Oto

Thanks for considering a contribution.

## Before You Start

- Open an issue first for large changes, feature proposals, or architectural shifts
- Keep pull requests focused and reviewable
- Do not commit local signing files, secrets, or machine-specific config

## Development Setup

1. Install dependencies:

```sh
bundle install
```

2. If you need local signing or device builds, copy:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

3. Build locally:

```sh
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=iOS Simulator,name=iPhone 17' build
```

4. Run tests:

```sh
xcodebuild -project Oto.xcodeproj -scheme Oto -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Pull Request Guidelines

- Explain the user-visible goal
- Describe the implementation tradeoffs
- Mention any follow-up work or known limitations
- Update docs when behavior or setup changes
- Keep identity-bearing values out of tracked files

## Commit Hygiene

- Prefer small, logical commits
- Include what was verified
- Avoid unrelated formatting-only churn

## Areas That Need Extra Care

- Signing and release automation
- Session persistence and privacy-sensitive storage
- Playback, download, and cache behavior
- Xcode project file changes
