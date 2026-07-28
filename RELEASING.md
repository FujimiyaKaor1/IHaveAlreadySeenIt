# Releasing

Public releases must be signed with Developer ID Application, notarized by Apple, and produced by the tag-triggered GitHub Actions workflow. Do not publish an unsigned preview as a normal-user build.

## Required GitHub secrets

- `DEVELOPER_ID_P12_BASE64`: base64-encoded Developer ID Application certificate and private key.
- `DEVELOPER_ID_P12_PASSWORD`: export password for the PKCS#12 file.
- `DEVELOPER_ID_APPLICATION`: complete codesign identity name.
- `DEVELOPER_TEAM_ID`: Apple developer team identifier used in the Helper client requirement.
- `RELEASE_KEYCHAIN_PASSWORD`: random, release-only temporary keychain password.
- `APPLE_NOTARY_KEY_P8_BASE64`: base64-encoded App Store Connect API private key.
- `APPLE_NOTARY_KEY_ID`: App Store Connect API key ID.
- `APPLE_NOTARY_ISSUER`: App Store Connect API issuer ID.

Never commit these values, print them in workflow output, or reuse the temporary keychain password elsewhere.

## Release sequence

1. Run `make coverage`, `swift build -c release`, and `scripts/package-app.sh` locally.
2. Test install and restore on a disposable macOS account or VM using a supported official WeChat copy.
3. Tag an reviewed commit as `vMAJOR.MINOR.PATCH` and push the tag only after explicit approval.
4. The workflow signs the app and Helper, notarizes and staples the app, creates a checksum, renders the Cask, and creates the GitHub Release.
5. Review the generated `ihavealreadyseenit.rb`, then copy it to `FujimiyaKaor1/homebrew-tap/Casks/` in a separately approved change.

The Cask template requires an exact archive SHA-256. Do not replace it with `:no_check`.
