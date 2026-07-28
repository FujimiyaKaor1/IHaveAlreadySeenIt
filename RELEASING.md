# Community release process

Community releases are free GitHub-only builds. They use an ad-hoc integrity signature and are **not Apple-notarized**. No Apple certificate, private key, notarization credential, Homebrew tap, or App Store account is used.

1. Run `make coverage`, `make app`, and `make dmg` locally.
2. Verify the DMG journey in a disposable macOS account or VM, including install, restore, repeat operations, insufficient permissions, and unknown-version refusal.
3. Review `git diff`, secret scans, the icon license record, and both languages.
4. Only after explicit approval, push the reviewed commit and a `vMAJOR.MINOR.PATCH` tag.
5. The tag workflow builds and mounts the DMG, then creates a **draft** GitHub Release. Review it manually before publication.

The first launch requires Finder → right-click → Open. Release notes must never instruct users to disable Gatekeeper or SIP, remove quarantine attributes, or run remote scripts through a shell.
