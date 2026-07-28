import IHaveAlreadySeenItCore
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            applicationPicker
            statusCard
            Spacer(minLength: 0)
            actionBar
        }
        .padding(24)
        .task { viewModel.refresh() }
        .alert("安装前请确认", isPresented: $viewModel.isShowingInstallConfirmation) {
            Button("取消", role: .cancel) {}
            Button("我理解风险，继续", role: .destructive) { viewModel.install() }
        } message: {
            Text("安装会修改微信主程序并破坏腾讯原始代码签名，可能影响更新、企业安全软件或账号风控。")
        }
        .alert("恢复原版微信", isPresented: $viewModel.isShowingRestoreConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { viewModel.restore() }
        } message: {
            Text("将使用经过官方签名验证的备份替换当前微信。")
        }
        .alert("操作未完成", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("好") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.planText != nil },
            set: { if !$0 { viewModel.planText = nil } }
        )) {
            planSheet
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("IHaveAlreadySeenIt")
                    .font(.largeTitle.bold())
                Text("本地、源码可审计的 macOS 微信防撤回实验工具")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.currentStage.map(stageText) ?? "正在检查…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var applicationPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
            Text(viewModel.appURL.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button("选择微信…") { viewModel.chooseApplication() }
            Button("重新检查") { viewModel.refresh() }
                .disabled(viewModel.isBusy)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var statusCard: some View {
        if let report = viewModel.report {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                statusRow("微信版本", "\(report.version) (\(report.build))")
                statusRow("架构", report.architectures.joined(separator: ", "))
                statusRow("官方签名", report.codeSignature.displayName)
                statusRow("兼容状态", compatibilityText(report.compatibility))
                statusRow("安装状态", installationText(report.installation))
                statusRow("备份状态", backupText(report.backup))
                statusRow("安全门", safetyGateText(report))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        } else if !viewModel.isBusy {
            ContentUnavailableView(
                "尚无检查结果",
                systemImage: "shield.lefthalf.filled",
                description: Text("选择微信后运行只读检查。")
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var actionBar: some View {
        let policy = UserActionPolicy(
            report: viewModel.report,
            isBusy: viewModel.isBusy,
            hasRecoverableBackupWithoutApplication: viewModel.hasRecoverableBackupWithoutApplication,
            allowsMutatingOperations: viewModel.allowsPrivilegedOperations
        )
        return HStack {
            Button("复制诊断报告") { viewModel.copyDiagnostics() }
                .disabled(viewModel.report == nil)
            Button("查看安装计划") { viewModel.preparePlan() }
                .disabled(!policy.canPlan)
            Spacer()
            Button("恢复原版") { viewModel.isShowingRestoreConfirmation = true }
                .disabled(!policy.canRestore)
            Button("安装", role: .destructive) {
                viewModel.isShowingInstallConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!policy.canInstall)
        }
    }

    private var planSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("只读安装计划").font(.title2.bold())
            Text(viewModel.planText ?? "")
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("关闭") { viewModel.planText = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func compatibilityText(_ value: CompatibilityDiagnostic) -> String {
        switch value {
        case .supported: return "已验证"
        case .unknownHash: return "哈希未知"
        case .unsupportedVersion: return "版本不支持"
        }
    }

    private func installationText(_ value: InstallationDiagnostic) -> String {
        switch value {
        case .notInstalled: return "未安装"
        case .installed(let architectures): return "已安装（\(architectures.joined(separator: ", "))）"
        case .partiallyInstalled(let architectures):
            return "不完整安装（\(architectures.joined(separator: ", "))）"
        }
    }

    private func backupText(_ value: BackupDiagnostic) -> String {
        switch value {
        case .missing: return "无"
        case .present: return "官方签名备份可用"
        case .invalid: return "备份无效"
        }
    }

    private func safetyGateText(_ report: DiagnosticReport) -> String {
        guard viewModel.allowsPrivilegedOperations else {
            return "只读预览（禁止变更）"
        }
        return report.isSafeToInstall ? "可以安装" : "禁止安装"
    }

    private func stageText(_ stage: InstallationStage) -> String {
        switch stage {
        case .validating: return "正在验证…"
        case .backingUp: return "正在备份…"
        case .staging: return "正在准备副本…"
        case .injecting: return "正在注入…"
        case .signing: return "正在签名…"
        case .verifying: return "正在复核…"
        case .replacing: return "正在替换应用…"
        case .writingState: return "正在保存状态…"
        case .completed: return "已完成"
        case .rollingBack: return "正在恢复原版…"
        }
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary)
            }
    }
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
