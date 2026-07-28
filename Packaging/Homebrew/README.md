# Homebrew distribution from the main repository

The IHaveAlreadySeenIt repository is also its Homebrew Tap. It distributes the ad-hoc signed
Community build directly from the published GitHub Release, and Homebrew verifies the pinned
SHA-256 before installing the App. No second repository or cross-repository credential is used.

## Install

```bash
brew tap FujimiyaKaor1/ihavealreadyseenit https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt.git
brew install --cask FujimiyaKaor1/ihavealreadyseenit/ihavealreadyseenit
```

The Community build is not Apple-notarized. On first launch, open Finder → Applications,
right-click IHaveAlreadySeenIt, choose Open, and confirm. Homebrew does not bypass Gatekeeper.

首次启动请在 Finder → 应用程序中右键 IHaveAlreadySeenIt，选择“打开”并确认。

## Upgrade

```bash
brew update
brew upgrade --cask ihavealreadyseenit
```

Upgrading replaces the manager only. It does not modify WeChat or delete the original backup.

## Uninstall safely

Before uninstalling, use the GUI to 恢复原版微信. Then run:

```bash
brew uninstall --cask ihavealreadyseenit
```

Homebrew removes the manager only. It does not restore a patched WeChat and does not delete
the safety backup. Source code, releases, and issue reporting are maintained in the
[IHaveAlreadySeenIt repository](https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt).
