# FAQ

## Is this an official WeChat plugin?

No. It is an open-source local patch manager. Community 1.0 only supports the exact verified WeChat `4.1.7 (34371)` build.

## Why must I right-click Open the first time?

The free Community build is ad-hoc signed but not notarized by Apple. macOS therefore requires an explicit first-open decision. Do not disable Gatekeeper or SIP and do not run `xattr` bypass commands.

## Why does it open Terminal?

Writing beside an app in `/Applications` can require administrator access. The GUI does not collect your password. It copies one fixed, quoted command that can only invoke the CLI embedded inside the same app for install or restore; you review it and enter your password in Terminal.

## Does it upload messages or account information?

No. There is no network access, telemetry, chat-database access, or automatic update. Diagnostics contain only app path, version/build, executable hash, architectures, signature state, local signature-match counts, install state, and backup state.

## What happens after a WeChat update?

The patch normally disappears or becomes unsupported. Run the check again. Unknown versions and hashes are always refused.

## How do I get help safely?

Copy the GUI diagnostic report or run the embedded `ihavealreadyseenit doctor --json`. Never upload chat data, account details, the WeChat executable, or backups.
