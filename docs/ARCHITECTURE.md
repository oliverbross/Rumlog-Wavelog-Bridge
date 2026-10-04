# Architecture

## Authority boundary

RUMlogNG and Wavelog remain authoritative for their own stored records. The
bridge owns only synchronization state: identity mappings, last-seen hashes,
outbox operations, delivery receipts, tombstones, and conflicts.

```text
RUMlogNG
  ↕ UDP discovery/change events + reliable TCP peer protocol
RUMlog peer adapter
  ↕ normalized operations
Sync coordinator ── durable ledger/outbox ── reconciliation
  ↕ normalized operations
Wavelog API v2 adapter
  ↕ HTTPS
Wavelog
```

The Wavelog API token requires `station:read`, `qso:read`, `qso:write`, and
`qso:delete`. Confirmation state uses the dedicated confirmation resource rather
than pretending those fields are editable through QSO `PATCH`.

The initial QSO adapter is aligned to Wavelog upstream commit
`3af1ba557a54da9ba318daf9d4a5ed8e937db1b8`. In that contract, JSON creates use
`station_profile_id` plus `import_type: json`; partial updates use `PATCH`; delete
returns HTTP 204; and read-side `freq`/`freq_rx` values are serialized as strings
containing Hz. A configured base URL must include `/index.php` on installations
whose routing requires it.

## Contact identity

Live RUMlog/N1MM messages carry a contact GUID. Wavelog uses an integer QSO ID.
The bridge stores both after the first accepted operation. Before that mapping
exists, bootstrap reconciliation uses a semantic identity derived from normalized
callsign, QSO timestamp, band, mode, and frequency.

Raw ADIF bytes are not an identity: tag order, formatting, and optional fields can
change without changing the contact.

## Delivery model

1. Persist intent before provider I/O.
2. Mark the operation `delivery_unknown` before an operation whose response could
   be lost after the remote side commits it.
3. Store the exact remote identity on a confirmed create.
4. Reconcile ambiguous outcomes by identity and content before retrying.
5. Never translate absence into deletion until a complete, scoped inventory has
   been obtained and the deletion policy permits it.

## Reconciliation

- RUMlog live peer events provide immediate local changes.
- Wavelog `since_id` accelerates retrieval of newly created rows only.
- Periodic full scoped snapshots detect edits, deletions, missed events, and
  mapping drift.
- Three-way comparison uses the last synchronized hashes. Concurrent edits become
  conflicts instead of silent last-writer-wins overwrites.

## Deployment

The product is macOS-only because the RUMlog side uses a native macOS application
and will eventually require Apple Events. The protocol core stays independent of
UI code so it can be tested from Swift Package Manager and embedded in a signed
menu-bar application later.
