# Changelog

All notable changes to KeepAlive. Each section becomes the description of the
matching GitHub release.

## [1.0.2] - 2026-10-06

### Fixed

- The activity log shows date and time on two lines, so the date column no longer
  wraps unevenly in English.
- The settings window can be made a little shorter.

### Documentation

- The README now shows a screenshot of KeepAlive.

## [1.0.1] - 2026-10-06

### Fixed

- The settings window no longer shows a sidebar button in the middle of the toolbar.
  The sidebar is now always visible, as in System Settings.

### Documentation

- Corrected how to open KeepAlive for the first time on macOS 15 and later.
- Added the missing setup steps: trusting your developer certificate on the iPhone,
  turning on Open at Login, and choosing a device when several are paired.

## [1.0] - 2026-10-06

The first release.

### Features

- Menu bar app that keeps the iOS apps you build yourself installed on your iPhone,
  even with a free Apple Account.
- Builds the Release configuration of each Xcode project or workspace you add and
  reinstalls it before the seven-day signature expires, over Wi‑Fi or a cable.
- Renews early, by default once an app is three days old, and warns you when an app
  is about to expire.
- Saves energy: macOS schedules the checks, and builds wait for a power adapter unless
  an app expires within a day.
- Leaves no build files behind and adds nothing to your project folders.
- Settings with a sidebar for apps, device and activity, in English and German.
- Uses only Apple’s own tools and the Apple Account you are signed in with in Xcode.
  KeepAlive never asks for your password.
