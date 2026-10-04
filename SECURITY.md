# Security

## Reporting

Please report vulnerabilities privately to the repository owner before publishing
details that could expose operators' logbooks, Wavelog credentials, or local
network services.

## Security boundaries

- Wavelog tokens must never be written to logs, captures, fixtures, or Git.
- Production tokens belong in the macOS Keychain when the app target is added.
- Protocol captures may contain personal and station information and are ignored
  by Git by default.
- Peer listeners default to local/trusted interfaces and must not be publicly
  exposed.
- RUMlog databases are not modified directly.
- Remote deletions remain opt-in until identity, scope, and complete inventory are
  verified.
- Provider timeouts and lost responses are ambiguous outcomes, not proof of
  failure; the bridge reconciles before retrying.
