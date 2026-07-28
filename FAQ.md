# FAQ

## Is this an official WeChat plugin?

No. It is an experimental local patch manager. It modifies the installed application and ad-hoc re-signs it after explicit confirmation.

## Does it upload messages or account information?

No. The app has no networking, telemetry, account access, or chat-database access. Diagnostic reports contain only application path, version/build, executable hash, architectures, code-signature state, signature-match counts, installation state, and backup state.

## Why is my version blocked?

Only exact, independently verified builds are accepted. A matching version number is not enough because different distributions may contain different executables.

## What happens after a WeChat update?

The patch will normally be removed or become unsupported. Run the read-only check again. The tool never automatically patches an unknown update.

## Why does the GUI ask for administrator approval?

Writing to `/Applications` requires elevated privileges. Signed releases use a narrowly scoped ServiceManagement helper that only supports install and restore operations; unsigned preview builds cannot perform those operations.

## How do I get help safely?

Copy the GUI diagnostic report or run `ihavealreadyseenit doctor --json`. Never upload chat data, account details, the WeChat executable, or application backups.
