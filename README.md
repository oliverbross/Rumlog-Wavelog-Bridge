# RUMlog–Wavelog Bridge

A macOS-native agent that will synchronize RUMlogNG with Wavelog by speaking
RUMlog's network peer protocol on one side and Wavelog API v2 on the other.

The project is intentionally starting with protocol discovery. RUMlog documents
its UDP announcements and its RUMlog-to-RUMlog synchronization behavior, but the
reliable TCP peer exchange is not publicly specified. The first executable is a
passive recorder and parser so the protocol can be documented from disposable
test logbooks before the bridge sends any peer traffic.

## Current status

- Native Swift 6 package for macOS 13 and newer.
- Passive UDP recorder for `contactinfo`, `contactreplace`, `contactdelete`, and
  `appinfo` XML messages.
- Confirmed passive `AppInfo` capture from an installed RUMlogNG 6.5.1 client;
  observed announcements arrived about every seven seconds on loopback.
- Semantic QSO identity model for deduplication and loop suppression.
- Durable local link/outbox ledger with explicit `delivery_unknown` state.
- Initial typed Wavelog API v2 client for QSO list, create, patch, and delete
  operations, aligned with the current upstream resource contract.
- No direct writes to RUMlog `.rlog` databases.
- No active RUMlog peer emulation yet; that waits for captured protocol evidence.

## Build and test

```bash
swift build
swift test
```

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

- The bridge presents a RUMlog-compatible peer; Wavelog itself remains behind
  its authenticated API.
- New, edited, deleted, and confirmation-state operations are mapped through a
  durable identity ledger.
- Network failures enter a durable outbox before provider I/O. Ambiguous outcomes
  become `delivery_unknown` and are reconciled rather than blindly retried.
- Initial bootstrap and periodic repair use full snapshots. Wavelog `since_id`
  is only an optimization for newly created contacts.
- Automatic deletion remains disabled until both directions are proven against
  disposable logbooks.

See [Architecture](docs/ARCHITECTURE.md) and
[Protocol discovery](docs/PROTOCOL_DISCOVERY.md).

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
