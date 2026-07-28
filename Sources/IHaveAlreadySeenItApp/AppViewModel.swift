import AppKit
import Foundation
import IHaveAlreadySeenItCore
import Observation

@Observable
@MainActor
final class AppViewModel {
    var appURL = URL(fileURLWithPath: "/Applications/WeChat.app", isDirectory: true)
    let allowsPrivilegedOperations: Bool
    private(set) var report: DiagnosticReport?
    private(set) var isBusy = false
    private(set) var currentStage: InstallationStage?
    private(set) var hasRecoverableBackupWithoutApplication = false
    var errorMessage: String?
    var planText: String?
    var isShowingInstallConfirmation = false
    var isShowingRestoreConfirmation = false

    init(
        allowsPrivilegedOperations: Bool = AppRuntimeCapabilities.allowsPrivilegedOperations()
    ) {
        self.allowsPrivilegedOperations = allowsPrivilegedOperations
    }

    func refresh() {
        let selectedURL = appURL
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                report = try await Task.detached {
                    try DiagnosticService().report(appURL: selectedURL)
                }.value
                hasRecoverableBackupWithoutApplication = false
            } catch {
                report = nil
                hasRecoverableBackupWithoutApplication = await Task.detached {
                    DiagnosticService().backupStatus(appURL: selectedURL) == .present
                }.value
                errorMessage = Self.userMessage(for: error)
            }
        }
    }

    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择 WeChat.app"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = appURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        appURL = selected
        refresh()
    }

    func preparePlan() {
        let selectedURL = appURL
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                planText = try await Task.detached {
                    let report = try ApplicationInspector().inspect(appURL: selectedURL)
                    let executable = try Data(contentsOf: report.executableURL, options: .mappedIfSafe)
                    _ = try PatchPlanner.prepareExecutable(executable, report: report)
                    return """
                    1. 验证官方签名、版本、Build、SHA-256 与双架构特征。
                    2. 完整备份原始 WeChat.app 并再次验证腾讯签名。
                    3. 本机编译 Universal Hook，在暂存副本中注入 LC_LOAD_DYLIB。
                    4. 对暂存副本执行 ad-hoc 签名并验证注入结果。
                    5. 原子替换应用；任一步骤失败都会恢复原版。

                    预演通过，尚未修改任何文件。
                    """
                }.value
            } catch {
                planText = nil
                errorMessage = Self.userMessage(for: error)
            }
        }
    }

    func install() {
        perform(.install)
    }

    func restore() {
        perform(.restore)
    }

    func copyDiagnostics() {
        guard let report, let text = try? DiagnosticReportEncoder.jsonString(report) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func perform(_ operation: PrivilegedOperation) {
        guard allowsPrivilegedOperations else {
            errorMessage = "当前是未签名只读预览版，安装与恢复功能不可用。"
            return
        }
        let selectedURL = appURL
        isBusy = true
        currentStage = .validating
        errorMessage = nil
        Task {
            defer {
                isBusy = false
                currentStage = nil
            }
            do {
                try await PrivilegedHelperClient().perform(operation, appURL: selectedURL)
                currentStage = .completed
                report = try await Task.detached {
                    try DiagnosticService().report(appURL: selectedURL)
                }.value
                hasRecoverableBackupWithoutApplication = false
            } catch {
                errorMessage = Self.userMessage(for: error)
            }
        }
    }

    private static func userMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        switch error {
        case ApplicationInspectionError.appNotFound:
            return "没有找到微信，请选择正确的 WeChat.app。"
        case ApplicationInspectionError.unexpectedBundleIdentifier:
            return "所选应用不是官方微信 Bundle。"
        case PatchPlanningError.unsupportedVersion:
            return "当前微信版本尚未经过验证，不会修改任何文件。"
        case PatchPlanningError.unknownExecutableHash:
            return "当前微信可执行文件哈希未知，不会修改任何文件。"
        default:
            return "操作未完成：\(String(describing: error))"
        }
    }
}
