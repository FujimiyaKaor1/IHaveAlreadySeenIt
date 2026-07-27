# WeChatGuard

WeChatGuard 是一个本地、源码可审计的 macOS 微信防撤回实验工具。它结合了两类思路：

- 使用版本、build、SHA-256 和机器码特征进行严格匹配，并提供完整备份与恢复。
- 在 macOS 上从源码编译一个极小动态库，通过 `LC_LOAD_DYLIB` 加载后在内存中关闭撤回判断。

当前规则仅允许本机已检查的微信 `4.1.7 (34371)`，可执行文件 SHA-256：

```text
764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c
```

其他版本、build 或哈希会默认拒绝安装。不要为了绕过检查而随意添加未知哈希。

## 隐私边界

WeChatGuard：

- 不访问网络，也没有遥测或自动更新。
- 不安装 LaunchAgent，不常驻后台。
- 不使用 LLDB，不附加微信进程。
- 不读取聊天数据库、消息正文、联系人或登录账号。
- 不包含预编译注入器；hook 在安装时由本机 `clang` 从源码编译。
- 日志只写 hook 是否成功到 `/tmp/wechatguard-hook.log`。

## 仍然存在的风险

安装会修改 `/Applications/WeChat.app` 的主程序、加入动态库并进行 ad-hoc 重签名。这会破坏腾讯原始代码签名，可能触发 macOS、微信更新器、企业安全软件或账号风控。微信更新后补丁通常会失效。

当前 hook 把匹配到的撤回判断固定为 false，因此“自己撤回”在本机的显示也可能与官方客户端不同。服务端行为不由本工具控制。

本项目不会自动修改真实微信。请先运行只读检查和预演，并自行决定是否接受风险。

## 构建

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools：

```bash
xcode-select --install
make test
make build
```

生成的命令位于 `.build/release/wechatguard`。建议从源码在目标机器上本地构建，不要直接复用他人提供的二进制。

## 使用

只读检查：

```bash
.build/release/wechatguard inspect
```

完整预演，包括在内存中验证 Mach-O 注入，不写文件：

```bash
.build/release/wechatguard plan
```

安装前请退出微信。确认接受风险后：

```bash
sudo .build/release/wechatguard install --confirm-i-understand
```

安装器会先把完整原始应用备份到 `/Applications/.WeChatGuardBackup/Original-WeChat.bundle`。任一步骤失败都会尝试自动恢复。

卸载并恢复腾讯原始签名版本：

```bash
sudo .build/release/wechatguard uninstall
```

## 安全门

安装必须同时满足：

1. Bundle ID 为 `com.tencent.xinWeChat`。
2. 版本、build 和 SHA-256 命中本地允许规则。
3. 主程序同时包含 arm64 与 x86_64。
4. 两种架构的撤回函数特征码分别且仅命中一次。
5. Mach-O 头部有足够的零填充空间，不覆盖任何 section。
6. 微信进程已退出，应用和父目录可写。
7. 安装后 load command 与代码签名验证通过。

## 项目结构

```text
Sources/WeChatGuardCore/       版本、哈希、Mach-O、预检核心
Sources/wechatguard/           CLI、安装事务、备份恢复
Sources/wechatguard/Resources/ 可审计 hook 源码与最小权限 entitlements
Tests/WeChatGuardCoreTests/    无管理员权限、无真实应用写入的测试
```

## 致谢与许可

设计参考了 `a244573118/WeChatIntercept` 的 macOS 动态注入思路，以及 `huiyadanli/RevokeMsgPatcher` 的版本规则、备份恢复和失败即停思路。本项目没有复用两者仓库中的预编译二进制。

项目以 GPL-3.0 许可发布，仅用于本地研究与测试。使用者需自行遵守适用法律、软件许可和平台规则。
