cask "ihavealreadyseenit" do
  version "1.0.2"
  sha256 "bcaa1194f174a7de2855b08e4f08364bb1600c76fddf4b68d06c71be9288de61"

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
