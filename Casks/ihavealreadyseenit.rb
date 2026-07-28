cask "ihavealreadyseenit" do
  version "1.0.0"
  sha256 "56bec80c5810fc953ede9a786154a6939caf11b77e4c0c74f8c4512446c6ac60"

  url "https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt/releases/download/v#{version}/IHaveAlreadySeenIt-#{version}-Community.dmg"
  name "IHaveAlreadySeenIt"
  desc "Manage a local, reversible anti-revoke patch for WeChat"
  homepage "https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "IHaveAlreadySeenIt.app"

  caveats <<~EOS
    IHaveAlreadySeenIt Community is ad-hoc signed and is not Apple-notarized.
    On first launch, open Finder → Applications, right-click IHaveAlreadySeenIt,
    choose Open, and confirm. Homebrew does not bypass Gatekeeper.

    首次启动请在 Finder → 应用程序中右键 IHaveAlreadySeenIt，选择“打开”并确认。
    Homebrew 不会绕过 Gatekeeper，也不会代替 GUI 获取管理员权限。

    Before running `brew uninstall --cask ihavealreadyseenit`, restore the original
    WeChat from the GUI. Homebrew removes this manager only; it does not restore WeChat.

    执行 `brew uninstall --cask ihavealreadyseenit` 前，请先在 GUI 中“恢复原版微信”。
    Homebrew 只移除此管理工具，不会自动恢复微信或删除其安全备份。
  EOS
end
