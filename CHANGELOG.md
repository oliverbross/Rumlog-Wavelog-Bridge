# Changelog

## 0.2.2 — 2026-10-07

Reliability release by Oliver Bross OM0RX.

- Fixes a repeatable crash in edit reconciliation when Wavelog pagination
  includes the same QSO ID in more than one page.
- Keeps new-contact synchronization running while the optional RUMlog edit peer
  is disconnected; edit reconciliation resumes after the peer reconnects.
- Replaces one-minute complete local-logbook scans with a durable SQLite row-ID
  checkpoint and a bounded upgrade-recovery window.
- Runs the first lightweight automatic contact cycle after five seconds, then
  follows the configured interval.
- Persists the successful full-reconciliation time and gives startup contact sync
  a five-minute head start before an overdue full edit scan.
- Applies a five-minute retry floor after a failed full reconciliation so a
  transient provider error cannot trigger another expensive inventory every minute.
- Advertises the edit peer from the active local interface with broadcast, so
  RUMlog can distinguish the bridge from itself and discovery remains reliable
  when another local app also uses UDP port 12060. Incoming TCP is accepted only
  from this Mac's own interface address.
- Adds regression coverage for repeated Wavelog page rows, legacy state migration,
  and live read-only incremental SQLite access.

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
