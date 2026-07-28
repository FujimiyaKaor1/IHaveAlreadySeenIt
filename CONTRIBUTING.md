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

A new rule requires an untouched officially signed application, exact version and build, executable SHA-256, one verified signature match per architecture, and successful install/restore testing. Do not submit the application binary or user data.

## Pull requests

Explain the safety invariant being changed, include failure-path tests, run the complete verification suite, and review the final diff for credentials and generated binaries.
