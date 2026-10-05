# Changelog

## 0.2.1 — 2026-10-05

Official project release by Oliver Bross OM0RX.

- Adds the live application screenshot and complete release, setup, operation,
  architecture, audit, repair, build, and license documentation.
- Refreshes the displayed RUMlogNG process count whenever the native peer connects
  or disconnects, so the interface cannot retain a stale instance indicator.
- Publishes a Developer ID signed macOS 13+ application under GPL-3.0-only.
  This release is not yet Apple-notarized; follow the first-launch instructions in
  the README.

## 0.2.0 — 2026-10-05

First public signed release by Oliver Bross OM0RX.

- Adds automatic new-contact synchronization between RUMlogNG and Wavelog API v2.
- Adds two-way edit reconciliation with destination readback verification.
- Uses RUMlogNG's native peer protocol for edit replacement without writing to
  `.rlog` databases.
- Stores the Wavelog token in macOS Keychain and keeps synchronization state
  isolated per Wavelog station profile.
- Holds ambiguous concurrent changes and deletions for operator review.
- Includes a Developer ID signed macOS 13+ application. This release is not yet
  Apple-notarized; follow the first-launch instructions in the README.
