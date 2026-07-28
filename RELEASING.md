# Community release process

Community releases are free GitHub builds distributed directly and through the personal
`FujimiyaKaor1/homebrew-tap`. They use an ad-hoc integrity signature and are **not
Apple-notarized**. No Apple certificate, private key, notarization credential, or App Store
account is used.

1. Run `make coverage`, `make app`, and `make dmg` locally.
2. Verify the DMG journey in a disposable macOS account or VM, including install, restore, repeat operations, insufficient permissions, and unknown-version refusal.
3. Review `git diff`, secret scans, the icon license record, and both languages.
4. Run `make homebrew-audit`; confirm the generated Cask contains no `no_quarantine`, shell
   command, preflight mutation, or backup-removal stanza.
5. Only after explicit approval, push the reviewed commit and a `vMAJOR.MINOR.PATCH` tag.
6. The tag workflow builds and mounts the DMG, generates a Cask from that exact DMG checksum,
   then creates a **draft** GitHub Release. Review it manually before publication.
7. Publish the Release before updating the Tap. Then manually run the `Sync Homebrew Tap`
   workflow with the stable version. It verifies the published GitHub asset digest before
   committing to the Tap.
8. Test `brew install`, `brew upgrade`, and safe uninstall in a disposable macOS account or VM.

`HOMEBREW_TAP_TOKEN` must be a fine-grained token with contents read/write access only to
`FujimiyaKaor1/homebrew-tap`. Store it only as an encrypted Actions secret. Never place it in
the repository, logs, release notes, or Cask.

If a Cask release is faulty, restore the last known-good version and SHA-256 in the Tap. Never
replace an existing GitHub Release asset in place. Users recover through `brew update` followed
by `brew reinstall --cask ihavealreadyseenit`.

The first launch requires Finder → right-click → Open. Release notes must never instruct users to disable Gatekeeper or SIP, remove quarantine attributes, or run remote scripts through a shell.
