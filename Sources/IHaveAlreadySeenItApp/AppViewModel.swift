import AppKit
import Foundation
import IHaveAlreadySeenItCore
import Observation

@Observable
@MainActor
final class AppViewModel {
    var appURL = URL(fileURLWithPath: "/Applications/WeChat.app", isDirectory: true)
    let mutationBackend: AppMutationBackend
    private(set) var report: DiagnosticReport?
    private(set) var isBusy = false
    private(set) var currentStage: InstallationStage?
    private(set) var hasRecoverableBackupWithoutApplication = false
    var errorMessage: String?
    var planText: String?
    var isShowingInstallConfirmation = false
    var isShowingRestoreConfirmation = false
    var administratorCommand: String?
    var isShowingAdministratorInstructions = false
    private(set) var operationSucceeded = false

    var allowsMutatingOperations: Bool {
        mutationBackend.allowsMutatingOperations
    }

    init(
        mutationBackend: AppMutationBackend = AppRuntimeCapabilities.mutationBackend()
    ) {
        self.mutationBackend = mutationBackend
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
        panel.title = L10n.text("action.choose")
        panel.prompt = L10n.text("action.choose")
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
                    if L10n.isSimplifiedChinese {
                        return """
                        1. 验证官方签名、版本、Build、SHA-256 与双架构特征。
                        2. 完整备份原始 WeChat.app 并再次验证腾讯签名。
                        3. 本机编译 Universal Hook，在暂存副本中注入 LC_LOAD_DYLIB。
                        4. 对暂存副本执行 ad-hoc 签名并验证注入结果。
                        5. 原子替换应用；任一步骤失败都会恢复原版。

                        预演通过，尚未修改任何文件。
                        """
                    }
                    return """
                    1. Verify the official signature, version, build, SHA-256, and both architecture signatures.
                    2. Back up the complete WeChat.app and verify Tencent's signature again.
                    3. Compile the universal hook locally and inject LC_LOAD_DYLIB into a staged copy.
                    4. Ad-hoc sign and verify the staged copy.
                    5. Atomically replace the app; restore the original if any stage fails.

                    Dry run passed. No files were changed.
                    """
                }.value
            } catch {
                planText = nil
                errorMessage = Self.userMessage(for: error)
            }
        }
    }

    func install() {
        requestGracefulQuitThenPerform(.install)
    }

    func restore() {
        requestGracefulQuitThenPerform(.restore)
    }

    func launchWeChat() {
        NSWorkspace.shared.open(appURL)
    }

    func requestVersionSupport() {
        guard let url = URL(
            string: "https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt/issues/new?template=version_support.yml"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyAdministratorCommandAndOpenTerminal() {
        guard let administratorCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(administratorCommand, forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    func copyDiagnostics() {
        guard let report, let text = try? DiagnosticReportEncoder.jsonString(report) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func requestGracefulQuitThenPerform(_ operation: PrivilegedOperation) {
        isBusy = true
        errorMessage = nil
        Task {
            let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: ApplicationInspector.expectedBundleIdentifier
            )
            running.forEach { _ = $0.terminate() }
            for _ in 0..<20 where !running.allSatisfy({ $0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard running.allSatisfy({ $0.isTerminated }) else {
                isBusy = false
                errorMessage = Self.userMessage(for: InstallationServiceError.weChatIsRunning)
                return
            }
            isBusy = false
            perform(operation)
        }
    }

    private func perform(_ operation: PrivilegedOperation) {
        guard mutationBackend.allowsMutatingOperations else {
            errorMessage = "当前是未签名只读预览版，安装与恢复功能不可用。"
            return
        }
        let selectedURL = appURL
        isBusy = true
        currentStage = .validating
        operationSucceeded = false
        errorMessage = nil
        Task {
            defer {
                isBusy = false
                currentStage = nil
            }
            do {
                switch mutationBackend {
                case .readOnly:
                    throw PrivilegedHelperClientError.readOnlyPreview
                case .privilegedHelper:
                    try await PrivilegedHelperClient().perform(operation, appURL: selectedURL)
                case .localDevelopment:
                    try await Task.detached {
                        let service = try InstallationService.bundled()
                        let progress: (InstallationStage) -> Void = { stage in
                            Task { @MainActor in self.currentStage = stage }
                        }
                        switch operation {
                        case .install:
                            let report = try ApplicationInspector().inspect(appURL: selectedURL)
                            try service.install(appURL: selectedURL, report: report, progress: progress)
                        case .restore:
                            try service.restore(appURL: selectedURL, progress: progress)
                        }
                    }.value
                }
                currentStage = .completed
                report = try await Task.detached {
                    try DiagnosticService().report(appURL: selectedURL)
                }.value
                hasRecoverableBackupWithoutApplication = false
                operationSucceeded = true
            } catch {
                let needsAdministrator = {
                    if case InstallationServiceError.needsPrivileges = error { return true }
                    if case ApplicationPathValidationError.parentNotWritable = error { return true }
                    return false
                }()
                if needsAdministrator {
                    do {
                        let builder = AdministratorCommandBuilder(toolBundleURL: Bundle.main.bundleURL)
                        administratorCommand = try builder.command(
                            for: {
                                switch operation {
                                case .install: return AdministratorOperation.install
                                case .restore: return AdministratorOperation.restore
                                }
                            }(),
                            appURL: selectedURL
                        )
                        isShowingAdministratorInstructions = true
                    } catch {
                        errorMessage = Self.userMessage(for: error)
                    }
                } else {
                    errorMessage = Self.userMessage(for: error)
                }
            }
        }
    }

    private static func userMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        switch error {
        case ApplicationInspectionError.appNotFound:
            return L10n.isSimplifiedChinese ? "没有找到微信，请选择正确的 WeChat.app。" : "WeChat was not found. Choose the correct WeChat.app."
        case ApplicationInspectionError.unexpectedBundleIdentifier:
            return L10n.isSimplifiedChinese ? "所选应用不是官方微信 Bundle。" : "The selected app is not the official WeChat bundle."
        case PatchPlanningError.unsupportedVersion:
            return L10n.isSimplifiedChinese ? "当前微信版本尚未经过验证，不会修改任何文件。" : "This WeChat version has not been verified. No files were changed."
        case PatchPlanningError.unknownExecutableHash:
            return L10n.isSimplifiedChinese ? "当前微信可执行文件哈希未知，不会修改任何文件。" : "This WeChat executable hash is unknown. No files were changed."
        case PatchPlanningError.architectureHashMismatch:
            return L10n.isSimplifiedChinese ? "微信的架构哈希与验证配置不一致，不会修改任何文件。" : "The architecture hashes do not match the verified profile. No files were changed."
        case PatchPlanningError.candidateVersion:
            return L10n.isSimplifiedChinese ? "这是候选版本，只能诊断，完成真实安装与恢复验证前不能安装。" : "This is a diagnostic-only candidate and cannot be installed before real install and restore validation."
        case PatchPlanningError.insufficientHeaderSpace:
            return L10n.isSimplifiedChinese ? "微信主程序没有足够的安全注入空间，不会修改任何文件。" : "The executable lacks the required safe injection space. No files were changed."
        case InstallationServiceError.weChatIsRunning:
            return L10n.isSimplifiedChinese ? "微信仍在运行。请正常退出后重试；工具不会强制结束微信。" : "WeChat is still running. Quit it normally and try again; the tool will not force quit it."
        default:
            return L10n.isSimplifiedChinese ? "操作未完成：\(String(describing: error))" : "The operation did not complete: \(String(describing: error))"
        }
    }
}
