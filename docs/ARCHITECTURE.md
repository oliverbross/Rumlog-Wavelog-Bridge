# Architecture

## Authority boundary

RUMlogNG and Wavelog remain authoritative for their own stored records. The
bridge owns only synchronization state: identity mappings, last-seen hashes,
outbox operations, delivery receipts, tombstones, and conflicts.

```text
RUMlogNG
  ↕ supported Apple-event ADIF import/export
RUMlog adapter ── passive N1MM/peer discovery probe
  ↕ normalized operations
Sync coordinator ── durable ledger/outbox ── reconciliation
  ↕ normalized operations
Wavelog API v2 adapter
  ↕ HTTPS
Wavelog
```

The Wavelog API token requires `station:read`, `qso:read`, and `qso:write` for
the implemented new-contact flow. The confirmation resource is read-only; the
bridge does not pretend later confirmation changes are writable through QSO
`PATCH`. Edit/delete propagation remains disabled while the peer contract is
unproven.

The initial QSO adapter is aligned to Wavelog upstream commit
`3af1ba557a54da9ba318daf9d4a5ed8e937db1b8`. In that contract, JSON creates use
`station_profile_id` plus `import_type: adif` preserves provider-supported ADIF
fields and server-side duplicate detection; partial updates use `PATCH`; delete
returns HTTP 204; and read-side `freq`/`freq_rx` values are serialized as strings
containing Hz. A configured base URL must include `/index.php` on installations
whose routing requires it.

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

- RUMlog ADIF export with a five-minute overlap discovers newly logged contacts.
- Wavelog `since_id` accelerates retrieval of newly created rows only.
- Initial bootstrap checkpoints Wavelog's `lastfetchedid` cursor; crash recovery
  uses a full scoped RUMlog snapshot before resuming after that cursor.
- Edit/delete reconciliation is a planned peer-protocol layer and is not exposed
  as complete in the application.

## Deployment

The product is macOS-only because the RUMlog side uses Apple Events from a native
SwiftUI application. Exactly one RUMlogNG instance must be running so the target
open logbook is unambiguous. The protocol core remains independent of UI code and
is tested through Swift Package Manager.
