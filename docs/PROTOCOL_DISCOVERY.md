# RUMlog peer protocol discovery

The reliable RUMlog-to-RUMlog transport is not documented publicly. The results
below were derived in an isolated two-instance lab before the bridge was allowed
to advertise to the operator logbook.

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

## Confirmed active observations

- The source advertises `AppInfo` over UDP. A RUMlog instance with **Listen to
  other RUMlog instances** enabled discovers that source and initiates TCP to the
  advertised port.
- The stream is framed by the ASCII delimiter `B0UnDary_73`.
- An edit is emitted as `QsoDeleted` containing the old keyed archive, followed
  by `QsoLogged` containing the complete replacement archive.
- The payload is an NSKeyedArchiver graph whose root has Objective-C class name
  `QsoClass` and the field keys observed in RUMlogNG 6.5.1.
- The listening/importing RUMlog peer applies the replacement. The advertising
  source does not apply records sent back into its server socket, so the bridge
  must advertise and RUMlog must connect to it.
- A disposable receiver database was inspected before and after the exchange to
  prove the edit was committed; packet capture alone was not treated as proof.
- Ping messages are echoed and peer disconnect/reconnect is supported.

Historical replay, version negotiation, and confirmation-state replacement are
still intentionally outside the implemented contract. Automatic deletion is
also disabled.

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
