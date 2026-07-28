# Contributing

Contributions must preserve the fail-closed security model. Unknown versions, hashes, architectures, signatures, and ambiguous machine-code matches must be rejected.

## Development

```bash
swift build
swift test --enable-code-coverage
scripts/package-app.sh
```

Never run integration tests against the user's real `/Applications/WeChat.app`. Use a disposable account or VM and an application copy.

## Compatibility rules

A new rule requires an untouched officially signed application, exact version and build,
whole-executable and per-architecture SHA-256 values, one rule-specific signature match
per architecture, sufficient Mach-O header slack, and successful install/restore testing.
Do not submit the application binary, backup, logs, or user data.

Start with the read-only maintainer report:

```bash
make verify-version APP="/path/to/WeChat.app"
swift run ihavealreadyseenit verify-version --json --app "/path/to/WeChat.app"
```

Candidate profiles are diagnostic-only. Moving a profile to `verified` requires a real
copy install, launch, hook check, restore, official-signature recheck, and restored-hash
recheck. The shipped catalog intentionally allows no more than two verified builds.

## Pull requests

Explain the safety invariant being changed, include failure-path tests, run the complete verification suite, and review the final diff for credentials and generated binaries.
