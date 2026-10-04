# RUMlog–Wavelog Bridge

A macOS-native application that synchronizes RUMlogNG with Wavelog API v2.
It uses RUMlogNG's supported Apple-event ADIF interface for committed imports
and exports; the `.rlog` SQLite database is never modified directly.

## Current status

- Native SwiftUI application for macOS 13 and newer.
- Wavelog URL, secure API v2 token, and station-profile settings.
- API tokens stored in macOS Keychain, never in preferences or logs.
- Restart-safe, Wavelog-ID-cursor bootstrap with duplicate filtering.
- Automatic new-contact sync in both directions after bootstrap.
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
- Full edit/delete propagation remains disabled until the RUMlog peer protocol is
  captured and proven; Wavelog confirmation resources are read-only in API v2.

## Build and test

```bash
swift build
swift test
./scripts/package-app.sh
```

The packaged app is written to `dist/RUMlog-Wavelog-Bridge.app`. Copy it to
`/Applications`, launch RUMlogNG with the intended logbook, then open the bridge:

1. Enter the Wavelog base URL and API v2 token.
2. Test the connection and select a station profile.
3. Test the open RUMlogNG logbook.
4. Start the checkpointed bootstrap.
5. Enable automatic two-way sync after bootstrap completes.

On the first RUMlog test or sync, macOS may ask whether the bridge may control
RUMlogNG. Allow that request in System Settings → Privacy & Security → Automation;
without it, the supported Apple-event import/export interface cannot operate.

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
  documented scripting dictionary and observed N1MM-compatible UDP messages.
- New contacts are mapped through a durable identity ledger. Edit, delete, and
  confirmation-state operation types are reserved for later proven adapters and
  are not enabled in this build.
- Network failures enter a durable outbox before provider I/O. Ambiguous outcomes
  become `delivery_unknown` and are reconciled rather than blindly retried.
- Initial bootstrap uses cursor-paged ADIF and full semantic duplicate filtering.
  Wavelog `since_id` is used only for newly created contacts.
- Automatic deletion remains disabled until both directions are proven against
  disposable logbooks.

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

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
