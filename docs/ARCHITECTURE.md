# Architecture

## Authority boundary

RUMlogNG and Wavelog remain authoritative for their own stored records. The
bridge owns only synchronization state: identity mappings, last-seen hashes,
outbox operations, delivery receipts, tombstones, and conflicts.

```text
RUMlogNG
  ↓ read-only SQLite snapshot       ↑ Apple-event ADIF create
  ↕ native RUMlog peer replacement (`QsoDeleted` + `QsoLogged`)
RUMlog adapter ── UDP discovery/TCP peer service
  ↕ normalized operations
Sync coordinator ── durable ledger/outbox ── reconciliation
  ↕ normalized operations
Wavelog API v2 adapter
  ↕ HTTPS
Wavelog
```

The Wavelog API token requires `station:read`, `qso:read`, and `qso:write`. The
confirmation resource is read-only; the bridge does not pretend later
confirmation changes are writable through QSO `PATCH`. Contact deletions remain
disabled and are surfaced as held operations.

The initial QSO adapter is aligned to Wavelog upstream commit
`3af1ba557a54da9ba318daf9d4a5ed8e937db1b8`. In that contract, JSON creates use
`station_profile_id` plus `import_type: json` is used for typed JSON creates;
the running bridge uses `import_type: adif` for new-contact delivery to preserve
provider-supported ADIF fields and server-side duplicate detection. Partial
updates use `PATCH`; and delete returns HTTP 204. The public contract specifies
numeric-Hz `freq`/`freq_rx` responses, while deployed versions have also returned
numeric strings, so the adapter deliberately accepts both. A configured base URL
must include `/index.php` on installations whose routing requires it.

## Contact identity

Wavelog uses an integer QSO ID, while ADIF has no portable provider ID. Bootstrap
and live reconciliation therefore use a semantic identity derived from normalized
callsign, canonical QSO timestamp, band, and effective mode/submode. `TIME_OFF`
is preferred when present because RUMlog canonicalizes imported start time to the
ADIF end time. Frequency remains synchronized content but is not identity because
RUMlog rounds its precision. Captured live RUMlog/N1MM messages can additionally
carry replacement identity hints.

Raw ADIF bytes are not an identity: tag order, formatting, and optional fields can
change without changing the contact.

## Delivery model

1. Persist intent before provider I/O.
2. Mark the operation `delivery_unknown` before an operation whose response could
   be lost after the remote side commits it.
3. Treat Wavelog's ADIF duplicate skip as an idempotent delivery receipt.
4. Reconcile ambiguous inbound outcomes against a full RUMlog export before retrying.
5. Never translate absence into deletion until a complete, scoped inventory has
   been obtained and the deletion policy permits it.

## Reconciliation

- The selected `.rlog` file is opened with SQLite `READONLY` and
  `PRAGMA query_only=ON`; it is never modified by the bridge.
- RUMlog Apple-event ADIF remains the supported create/import path.
- RUMlog peer replacement is the write path for Wavelog-originated edits.
- Wavelog `since_id` accelerates retrieval of newly created rows only.
- Initial bootstrap checkpoints Wavelog's `lastfetchedid` cursor; crash recovery
  uses a full scoped RUMlog snapshot before resuming after that cursor.
- Full inventories are reconciled every five minutes for edits because
  `since_id` does not report updates to existing rows.
- Persisted per-contact snapshots identify which side changed. If both sides
  changed incompatibly, the bridge records a conflict instead of choosing a
  winner. Absence is held rather than translated into deletion.
- The synchronized edit intersection is callsign/date/time, band/RX band, mode,
  frequency, reports, grid, name, comment, QTH, state/county, IOTA, QSL route,
  power, CQ/ITU zones, and satellite name/mode. Provider-only propagation and
  SOTA/POTA/WWFF references remain untouched in Wavelog because RUMlogNG 6.5.1
  has no corresponding persistent columns.
- A destination readback must match the requested supported-field snapshot before
  its baseline advances. Failed or partial writes therefore remain retryable and
  visible instead of being silently accepted.

## Deployment

The product is macOS-only because the RUMlog side uses Apple Events and the
native peer service from a SwiftUI application. Exactly one RUMlogNG instance
must be running and the configured `.rlog` path must be the open logbook. The
protocol core remains independent of UI code and is tested through Swift Package
Manager.
