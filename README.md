# IHaveAlreadySeenIt

IHaveAlreadySeenIt 是一个免费、开源、仅在本机运行的 macOS 微信防撤回补丁管理器。Community 1.0 提供面向普通用户的 SwiftUI 图形界面，同时保留可审计 CLI、严格版本白名单、完整备份与事务回滚。

> 它不是微信官方插件。修改客户端可能产生兼容性、更新或账号风险，请在理解风险后自行决定是否使用。

## 下载与首次打开

Community Build 只通过 GitHub Releases 提供 DMG、源码和 SHA-256，不使用 App Store、Homebrew、Apple Developer Program 或公证。

1. 下载 `IHaveAlreadySeenIt-1.0.0-Community.dmg` 并核对 SHA-256。
2. 将 App 拖入 Applications。
3. 第一次启动时，在 Finder 中右键 App，选择“打开”。
4. 按首页唯一的主按钮操作；如果 `/Applications` 需要管理员权限，GUI 会复制固定命令并打开终端，由你检查后输入 macOS 密码。

不要关闭 Gatekeeper 或 SIP，不要执行 `xattr` 绕过命令，也不要运行 `curl | sh` 一类远程脚本。

## 界面

![IHaveAlreadySeenIt Community 界面](Documentation/community-1.0.png)

GUI 支持简体中文和英文，会跟随系统语言。浅色、深色、降低透明度、高对比度与减少动态效果均使用系统无障碍设置。

## 支持状态

| 微信版本 | Build | 架构 | 官方主程序 SHA-256 | 状态 |
|---|---:|---|---|---|
| 4.1.7 | 34371 | arm64 + x86_64 | `764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c` | 已验证 |

其他版本、Build、哈希或架构会安全拒绝，不进行模糊匹配。增加新版本必须重新提供官方样本证据、双架构唯一特征和安装/恢复验证。

内置规则按版本独立保存整包与架构 SHA-256、arm64/x86_64 特征、架构要求和最小 Mach-O 头部空间。候选规则只能生成诊断，不能安装；默认最多维护最近两个完成真实验证的构建。

当前规则的可审计验证记录见 [`Documentation/compatibility/wechat-macos-4.1.7-34371.md`](Documentation/compatibility/wechat-macos-4.1.7-34371.md)。

## 隐私与安全边界

- 不访问网络、无遥测、无自动上传、无自动更新。
- 不读取聊天数据库、消息正文、联系人或登录账号。
- 不安装后台常驻项，不附加微信进程。
- hook 在安装时由本机 `clang` 从仓库中的极小 C 源码编译。
- Community App 不包含、不安装、不注册 Privileged Helper。
- 权限不足时仅生成内嵌 CLI 的 `install` 或 `uninstall` 固定命令；路径会标准化并进行严格 shell 转义。
- 安装前验证 Bundle ID、腾讯 Team ID `5A4RE8SF68`、版本、Build、SHA-256、架构和唯一特征；任一条件不符即停止。
- 安装事务包含备份、暂存、注入、签名、验证、替换和状态写入；失败时自动回滚。

修改后的微信使用 ad-hoc 签名，不再保有腾讯原始代码签名。完整官方备份位于目标 App 旁的 `.IHaveAlreadySeenItBackup`，恢复操作会重新验证该备份。

## 从源码构建

要求 macOS 14+ 和 Xcode Command Line Tools：

```bash
xcode-select --install
make test
make coverage
make app
make install-local
make verify-version APP="/path/to/WeChat.app"
```

`make install-local` 只使用本仓库本地源码，不联网下载脚本；它构建 Community App、执行完整 ad-hoc 签名、复制到 `/Applications` 并启动。若当前用户不能写入 `/Applications`，脚本会停止并提示使用 Finder 拖入，不会自行提权。

生成 DMG：

```bash
make dmg
```

只读构建仍可显式生成：

```bash
BUILD_FLAVOR=read-only scripts/package-app.sh
```

## CLI

发布 App 内的 CLI 位于 `IHaveAlreadySeenIt.app/Contents/Helpers/ihavealreadyseenit`：

```bash
ihavealreadyseenit inspect --app /Applications/WeChat.app
ihavealreadyseenit plan --app /Applications/WeChat.app
ihavealreadyseenit doctor --json --app /Applications/WeChat.app
ihavealreadyseenit verify-version --json --app /Applications/WeChat.app
ihavealreadyseenit install --confirm-i-understand --app /Applications/WeChat.app
ihavealreadyseenit uninstall --app /Applications/WeChat.app
```

安装和恢复前只请求微信正常退出并等待；进程仍存在则停止，绝不强制结束。

`verify-version` 是维护者只读工具，会输出版本、Build、官方签名、整包和架构哈希、特征命中数与头部空间。它不会修改微信，也不会把候选版本加入安装白名单。

## 项目结构

```text
Sources/IHaveAlreadySeenItCore/   诊断、安全门、Mach-O 处理与事务安装服务
Sources/IHaveAlreadySeenItApp/    SwiftUI GUI、本地化与权限降级体验
Sources/ihavealreadyseenit/       可审计 CLI
Tests/                            故障注入、安全边界和状态决策测试
scripts/                          本机构建、图标、DMG 与 Community 发布脚本
```

未来正式签名版本的 Helper 基础代码目前保留在源码中供审计与研究，但 Community 打包脚本明确禁止将其放入 App。

## 图标授权

界面背景、图标源图、SHA-256 与授权状态见 [`Assets/README.md`](Assets/README.md)。构建脚本从完整正方形原图生成全部 macOS 图标尺寸，并将 4096×3072 背景图压缩为适合窗口显示的版本。图标只用于 Finder、Dock 和应用包，GUI 内容区不重复展示。

## 获取帮助与发布

提交 Issue 前请阅读 [FAQ](FAQ.md)，附上 `doctor --json`，但不要上传聊天数据、账号资料、微信二进制或备份。维护者流程见 [RELEASING.md](RELEASING.md)。Tag 工作流只创建草稿 Release，不读取任何 Apple 凭据。

本项目采用 GPL-3.0 许可，仅用于本地研究和个人选择。使用者需自行遵守适用法律、软件许可和平台规则。
