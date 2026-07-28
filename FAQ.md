# FAQ

## Is this an official WeChat plugin?

No. It is an open-source local patch manager. Community 1.0 only supports the exact verified WeChat `4.1.7 (34371)` build.

## Why must I right-click Open the first time?

The free Community build is ad-hoc signed but not notarized by Apple. macOS therefore requires an explicit first-open decision. Do not disable Gatekeeper or SIP and do not run `xattr` bypass commands.

## Does Homebrew remove the first-open confirmation?

No. Homebrew downloads the same GitHub Release DMG, verifies its pinned SHA-256, and installs
the App. Gatekeeper still requires Finder → right-click → Open for this non-notarized Community
build. The Cask does not use `no_quarantine` or any other bypass.

## What should I do before a Homebrew uninstall?

Restore the original WeChat from the GUI first. `brew uninstall --cask ihavealreadyseenit`
removes this manager only; it does not restore WeChat and does not delete the safety backup.

## Why does it open Terminal?

Writing beside an app in `/Applications` can require administrator access. The GUI does not collect your password. It copies one fixed, quoted command that can only invoke the CLI embedded inside the same app for install or restore; you review it and enter your password in Terminal.

## Does it upload messages or account information?

No. There is no network access, telemetry, chat-database access, or automatic update. Diagnostics contain only app path, version/build, executable hash, architectures, signature state, local signature-match counts, install state, and backup state.

## What happens after a WeChat update?

The patch normally disappears or becomes unsupported. Run the check again. Unknown versions and hashes are always refused.

## How can I request support for a new version?

Use the version-support issue template and paste the privacy-safe `doctor --json` output.
Maintainers use `verify-version --json` locally when reviewing an official app copy. Candidate
evidence never enables installation automatically. Do not upload WeChat.app, its executable,
backups, hook logs, account identifiers, or chat data.

## How do I get help safely?

Copy the GUI diagnostic report or run the embedded `ihavealreadyseenit doctor --json`. Never upload chat data, account details, the WeChat executable, or backups.
