# RUMlog–Wavelog Bridge

A macOS-native application by **Oliver Bross OM0RX** that synchronizes RUMlogNG
with Wavelog API v2.
It reads the selected `.rlog` logbook through a query-only SQLite connection,
uses RUMlogNG's Apple-event ADIF interface for new-contact imports, and uses the
native RUMlog-to-RUMlog peer stream for remote edits. The bridge never modifies
the `.rlog` database directly.

## Current status

- Native SwiftUI application for macOS 13 and newer.
- Wavelog URL, secure API v2 token, and station-profile settings.
- API tokens stored in macOS Keychain, never in preferences or logs.
- Restart-safe, Wavelog-ID-cursor bootstrap with duplicate filtering.
- Automatic new-contact sync in both directions after bootstrap.
- Full edit reconciliation in both directions for the fields that both products
  persist: QSO identity and time, frequency, band/RX band, mode, reports, grid,
  name, comment, QTH, state/county, IOTA, QSL route, power, CQ/ITU zones, and
  satellite name/mode.
- Proven native RUMlog peer transport for applying remote edits without direct
  `.rlog` writes: `QsoDeleted` followed by `QsoLogged` over the RUMlog TCP peer
  stream.
- Fast full-logbook scans through SQLite `READONLY` plus `PRAGMA query_only=ON`;
  the bridge never opens the operator logbook for writing.
- Five-minute automatic full reconciliation plus an on-demand sync action.
- Ambiguous concurrent edits and deletions are held and reported rather than
  guessed.
- Durable semantic-identity ledger and ambiguity-safe Wavelog outbox.
- Passive UDP recorder for `contactinfo`, `contactreplace`, `contactdelete`, and
  `appinfo` XML messages.
- Confirmed passive `AppInfo` capture from an installed RUMlogNG 6.5.1 client;
  observed announcements arrived about every seven seconds on loopback.
- Semantic QSO identity model for deduplication and loop suppression.
- Durable local link/outbox ledger with explicit `delivery_unknown` state.
- Typed Wavelog API v2 client for station discovery, paged JSON/ADIF QSO lists,
  create, patch, and delete operations.
- No direct writes to RUMlog `.rlog` databases.
- Developer ID signing is used automatically when an identity is available;
  notarization still requires an Apple notary profile on the packaging Mac.

## Install the signed release

1. Download `RUMlog-Wavelog-Bridge-0.2.0-macOS.zip` from the GitHub release.
2. Expand it and move `RUMlog-Wavelog-Bridge.app` to `/Applications`.
3. Open the app. Version 0.2.0 is signed with Oliver Bross OM0RX's Apple
   Developer ID.
   It is not notarized yet, so if macOS blocks the first launch, Control-click
   the app in Finder, choose **Open**, and confirm **Open** once.
4. Keep RUMlogNG open with the intended logbook before configuring the bridge.

The application is macOS-only and requires macOS 13 or newer.

## First-time configuration

1. In **Wavelog API v2**, enter the full Wavelog URL including `/index.php`,
   paste a `wl2_…` API v2 token with `station:read`, `qso:read`, and `qso:write`
   scopes, and choose **Save & Test Connection**. Select the correct station
   profile from the returned list. The token is saved only in macOS Keychain.
2. In **RUMlogNG**, choose the `.rlog` file that is currently open and keep the
   default peer port `12060` unless RUMlog is configured differently. Choose
   **Save & Test Open Logbook**; the bridge verifies that the latest contact in
   the selected file is visible through the running RUMlog instance.
3. In RUMlog Preferences → UDP, enable **Listen to other RUMlog instances** on
   the same port. In Window → Network, tick **Import** for **Wavelog Bridge**.
   The bridge must show **Peer connected**.
4. Choose **Start Bootstrap** once. It imports only Wavelog contacts that are
   not already present according to the semantic QSO identity and checkpoints
   every page so it can resume after interruption.
5. When bootstrap reports complete, choose **Sync Contacts & Changes Now**.
   After a successful manual cycle, enable **Automatic** and select the desired
   interval.

New contacts are checked each cycle. Existing-contact edits are checked on every
manual sync and at least every five minutes during automatic operation. Every
edit is read back from the destination before the reconciliation baseline moves.
If both sides changed, the record is reported as a conflict and left untouched.
Deletes and provider-only fields are held rather than guessed.

## Build and test from source

```bash
swift build
swift test
./scripts/package-app.sh
```

The packaged app is written to `dist/RUMlog-Wavelog-Bridge.app`. Packaging uses
the first available `Developer ID Application` identity unless
`CODE_SIGN_IDENTITY` is set explicitly. Without one it produces an ad-hoc signed
development build.

On the first RUMlog test or new-contact import, macOS may ask whether the bridge
may control RUMlogNG. Allow that request in System Settings → Privacy & Security
→ Automation; without it, the Apple-event ADIF interface cannot operate.

## Passive protocol probe

Check the configured App Info / logbook-change port in RUMlogNG Preferences →
UDP, then run:

```bash
swift run rumlog-probe --port 12060 --output captures/rumlog.ndjson
```

Useful options:

```text
--bind ADDRESS       IPv4 bind address (default: 0.0.0.0)
--port PORT          UDP port (default: 12060; verify in RUMlog)
--output PATH        Append newline-delimited JSON to a local file
--include-raw        Include raw XML in capture records
--max-packets COUNT  Exit after COUNT datagrams
--timeout SECONDS    Exit after an idle receive timeout
```

Captured QSO information can be personal data. Capture files are ignored by Git
and must never be committed without deliberate sanitization.

## Design boundaries

- Wavelog remains behind its authenticated API; RUMlog is accessed through its
  documented scripting dictionary, a strictly read-only SQLite snapshot, and
  its observed RUMlog-to-RUMlog peer protocol.
- New contacts are mapped through a durable identity ledger. Edit baselines are
  persisted separately so a restart does not turn an old difference into a new
  edit.
- Network failures enter a durable outbox before provider I/O. Ambiguous outcomes
  become `delivery_unknown` and are reconciled rather than blindly retried.
- Initial bootstrap uses cursor-paged ADIF and full semantic duplicate filtering.
  Wavelog `since_id` is used only for newly created contacts.
- Automatic deletion remains disabled. Confirmation-state changes are also held
  because Wavelog API v2 exposes those resources as read-only.
- Wavelog-only propagation and SOTA/POTA/WWFF reference fields are preserved on
  Wavelog but are not reported as synchronized because RUMlogNG 6.5.1 does not
  persist them in its logbook schema.

See [Architecture](docs/ARCHITECTURE.md) and
[Protocol discovery](docs/PROTOCOL_DISCOVERY.md).

## Audit and repair

`bridge-audit` is read-only: it compares all Wavelog and RUMlog contacts using
the provider-stable semantic identity and reports missing or extra unique QSOs.

```bash
WAVELOG_TOKEN=… WAVELOG_URL=https://host/index.php WAVELOG_STATION_ID=1 \
  swift run -c release bridge-audit
```

`bridge-repair` imports only the unique Wavelog contacts proven missing by that
same full comparison. It is deliberately gated and never writes to Wavelog:

```bash
RUN_REPAIR=1 WAVELOG_TOKEN=… WAVELOG_URL=https://host/index.php \
  WAVELOG_STATION_ID=1 swift run -c release bridge-repair
```

## Author and license

Copyright © 2026 Oliver Bross OM0RX.

GNU General Public License v3.0. See [LICENSE](LICENSE).
