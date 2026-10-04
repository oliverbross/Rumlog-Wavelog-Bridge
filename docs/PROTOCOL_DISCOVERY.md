# RUMlog peer protocol discovery

The reliable RUMlog-to-RUMlog transport is not yet documented publicly. Do not
guess the active TCP protocol and do not test against an operator's primary
logbook.

## Safety rules

- Use disposable `.rlog` files containing only synthetic contacts.
- Preserve the original application and bundle identifier.
- Do not patch, resign, or redistribute RUMlogNG.
- Keep captures local; they may contain callsigns and station metadata.
- Bind probes to loopback or a trusted LAN and never expose the peer protocol to
  the public internet.
- Back up disposable files before every destructive protocol experiment.

## Capture sequence

1. Record idle UDP traffic with App Info enabled.
2. Start a second disposable RUMlog peer and record discovery in both directions.
3. Enable Import and record TCP establishment, handshake, framing, and keepalive.
4. Create one synthetic QSO and record delivery and acknowledgement.
5. Edit a non-identity field.
6. Edit callsign and timestamp to expose replacement identity rules.
7. Change paper, LoTW, and eQSL states independently.
8. Delete the synthetic QSO.
9. Repeat create/edit/delete while the receiving peer is offline, then reconnect.
10. Replay duplicate and reordered messages only against disposable logbooks.

For each operation, record the source and destination database state before and
after the exchange. A packet capture alone is not proof that RUMlog accepted the
operation.

## Questions to resolve before active emulation

- Discovery port, cadence, broadcast address, and peer expiry.
- Application name/version checks and logbook identity.
- Which side initiates TCP and how the chosen port is announced.
- Message framing, encoding, acknowledgements, replay, and reconnect behavior.
- Whether a peer can request historical records or only receive future changes.
- Stable contact identity and replacement semantics.
- Loop prevention and forwarded/original markers.
- Conflict behavior when both peers edit the same contact offline.
- Version negotiation and behavior for unknown fields.

## Passive probe

`rumlog-probe` only binds a UDP socket and records datagrams. It does not advertise
itself, connect to RUMlog, or send traffic. The configured port must be verified in
RUMlogNG Preferences → UDP.

## Confirmed passive observations

Observed on 2026-10-04 with the installed RUMlogNG 6.5.1 client:

- With App Info enabled and its destination set to `127.0.0.1:12060`, RUMlog sent
  an `AppInfo` XML datagram approximately every seven seconds.
- Each observed datagram was 398 bytes and originated from one stable ephemeral
  UDP source port during the RUMlog session.
- The payload included application name, application version, station name,
  logbook filename, current band, and current/shown DXCC heading fields.
- The root and field names use mixed case (`AppInfo`, `Application`,
  `AppVersion`, and others); the probe normalizes names for typed parsing while
  optionally retaining the original XML in local captures.
- Two runs captured three consecutive announcements each. No QSO was created,
  edited, deleted, or otherwise changed to obtain this evidence.

The local capture files contain operator metadata, remain ignored by Git, and are
not part of the repository.
