import IHaveAlreadySeenItCore
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    @AppStorage("hasCompletedCommunityOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            CommunityBackground(
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    detailsCard
                    footer
                }
                .padding(28)
            }
            .safeAreaPadding(.top, 58)
        }
        .frame(minWidth: 720, minHeight: 600)
        .task { viewModel.refresh() }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) { onboarding }
        .sheet(isPresented: $viewModel.isShowingInstallConfirmation) { installConfirmation }
        .sheet(isPresented: $viewModel.isShowingAdministratorInstructions) { administratorSheet }
        .sheet(isPresented: Binding(
            get: { viewModel.planText != nil },
            set: { if !$0 { viewModel.planText = nil } }
        )) { planSheet }
        .confirmationDialog(
            L10n.text("action.restore"),
            isPresented: $viewModel.isShowingRestoreConfirmation
        ) {
            Button(L10n.text("action.restore"), role: .destructive) { viewModel.restore() }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        }
        .alert(L10n.text("error.title"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var presentation: CommunityHomePresentation {
        CommunityHomePresentation(
            report: viewModel.report,
            isBusy: viewModel.isBusy,
            backend: viewModel.mutationBackend,
            hasRecoverableBackupWithoutApplication: viewModel.hasRecoverableBackupWithoutApplication
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("IHaveAlreadySeenIt").font(.title.bold())
                Text(L10n.text("app.subtitle")).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(L10n.text("action.recheck"), systemImage: "arrow.clockwise") { viewModel.refresh() }
                Button(L10n.text("action.choose"), systemImage: "folder") { viewModel.chooseApplication() }
                Button(L10n.text("action.plan"), systemImage: "list.clipboard") { viewModel.preparePlan() }
                    .disabled(viewModel.report == nil)
                Divider()
                Button(L10n.text("action.copyDiagnostics"), systemImage: "doc.on.doc") { viewModel.copyDiagnostics() }
                    .disabled(viewModel.report == nil)
            } label: {
                Label(L10n.text("menu.more"), systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var hero: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14)).frame(width: 72, height: 72)
                Image(systemName: statusSymbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(statusTitle).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(statusDetail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if viewModel.operationSucceeded, presentation.status == .installed {
                    Button(L10n.text("action.launch"), systemImage: "play.fill") { viewModel.launchWeChat() }
                        .buttonStyle(.link)
                }
                if viewModel.isBusy {
                    ProgressView(value: stageProgress).tint(statusColor).padding(.top, 4)
                    Text(stageText(viewModel.currentStage ?? .validating)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            Button(primaryTitle) { performPrimaryAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(statusColor)
                .disabled(!presentation.isPrimaryEnabled)
        }
        .communityCard(solid: useSolidCards)
    }

    @ViewBuilder private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(L10n.text("card.wechat"), systemImage: "checkmark.shield").font(.headline)
            if let report = viewModel.report {
                DetailRow(label: L10n.text("field.path"), value: report.applicationPath)
                Divider()
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 11) {
                        DetailRow(label: L10n.text("field.version"), value: "\(report.version) (\(report.build))")
                        DetailRow(label: L10n.text("field.arch"), value: report.architectures.joined(separator: ", "))
                    }
                    VStack(spacing: 11) {
                        DetailRow(label: L10n.text("field.signature"), value: report.codeSignature.displayName)
                        DetailRow(label: L10n.text("field.compatibility"), value: compatibilityText(report.compatibility))
                        DetailRow(label: L10n.text("field.backup"), value: backupText(report.backup))
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.text("empty.title"), systemImage: "shield.lefthalf.filled",
                    description: Text(L10n.text("empty.detail"))
                ).frame(maxWidth: .infinity)
            }
        }
        .communityCard(solid: useSolidCards)
    }

    private var footer: some View {
        HStack {
            Label("Community 1.0 · macOS 14+", systemImage: "lock.shield")
            Spacer()
            Text("No telemetry · GPL-3.0")
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
    }

    private var onboarding: some View {
        VStack(spacing: 22) {
            Text(L10n.text("onboarding.title")).font(.largeTitle.bold())
            OnboardingRow(symbol: "checkmark.seal", text: L10n.text("onboarding.support"))
            OnboardingRow(symbol: "hand.raised", text: L10n.text("onboarding.privacy"))
            OnboardingRow(symbol: "arrow.counterclockwise", text: L10n.text("onboarding.backup"))
            Button(L10n.text("onboarding.start")) { hasCompletedOnboarding = true }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.pink)
        }.padding(36).frame(width: 540)
    }

    private var installConfirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("risk.title")).font(.title.bold())
            RiskRow(symbol: "externaldrive.badge.checkmark", text: L10n.text("risk.backup"))
            RiskRow(symbol: "signature", text: L10n.text("risk.signature"))
            RiskRow(symbol: "exclamationmark.shield", text: L10n.text("risk.account"))
            RiskRow(symbol: "power", text: L10n.text("risk.quit"))
            HStack {
                Button(L10n.text("action.cancel"), role: .cancel) { viewModel.isShowingInstallConfirmation = false }
                Spacer()
                Button(L10n.text("action.continue"), role: .destructive) {
                    viewModel.isShowingInstallConfirmation = false
                    viewModel.install()
                }.buttonStyle(.borderedProminent).tint(.pink)
            }
        }.padding(30).frame(width: 580)
    }

    private var administratorSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("admin.title"), systemImage: "lock.shield").font(.title.bold())
            Text(L10n.text("admin.detail")).foregroundStyle(.secondary)
            Text(L10n.text("admin.command")).font(.headline)
            Text(viewModel.administratorCommand ?? "")
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Button(L10n.text("action.doneRecheck")) {
                    viewModel.isShowingAdministratorInstructions = false; viewModel.refresh()
                }
                Spacer()
                Button(L10n.text("action.copyTerminal")) { viewModel.copyAdministratorCommandAndOpenTerminal() }
                    .buttonStyle(.borderedProminent).tint(.pink)
            }
        }.padding(30).frame(width: 650)
    }

    private var planSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("plan.title")).font(.title2.bold())
            Text(viewModel.planText ?? "").textSelection(.enabled)
            HStack { Spacer(); Button(L10n.text("action.close")) { viewModel.planText = nil }.keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 600)
    }

    private var useSolidCards: Bool { reduceTransparency || contrast == .increased }
    private var statusColor: Color {
        switch presentation.status { case .readyToInstall: .pink; case .installed: .green; case .needsAttention: .orange; case .working: .blue }
    }
    private var statusSymbol: String {
        switch presentation.status { case .readyToInstall: "sparkles"; case .installed: "checkmark.shield.fill"; case .needsAttention: "exclamationmark.triangle.fill"; case .working: "hourglass" }
    }
    private var statusTitle: String {
        switch presentation.status { case .readyToInstall: L10n.text("status.ready"); case .installed: L10n.text("status.installed"); case .needsAttention: L10n.text("status.attention"); case .working: L10n.text("status.working") }
    }
    private var statusDetail: String { L10n.text("status.\(presentation.status == .readyToInstall ? "ready" : presentation.status == .installed ? "installed" : presentation.status == .needsAttention ? "attention" : "working").detail") }
    private var primaryTitle: String {
        switch presentation.primaryAction { case .install: L10n.text("action.install"); case .restore: L10n.text("action.restore"); case .recheck: L10n.text("action.recheck") }
    }
    private func performPrimaryAction() {
        switch presentation.primaryAction { case .install: viewModel.isShowingInstallConfirmation = true; case .restore: viewModel.isShowingRestoreConfirmation = true; case .recheck: viewModel.refresh() }
    }
    private var stageProgress: Double {
        guard let stage = viewModel.currentStage, let index = InstallationStage.allCases.firstIndex(of: stage) else { return 0 }
        return Double(index + 1) / Double(InstallationStage.allCases.count)
    }
    private func stageText(_ stage: InstallationStage) -> String { L10n.text("progress.\(stage.rawValue)") }
    private func compatibilityText(_ value: CompatibilityDiagnostic) -> String { switch value { case .supported: L10n.text("value.supported"); case .unknownHash: L10n.text("value.unknownHash"); case .unsupportedVersion: L10n.text("value.unsupported") } }
    private func backupText(_ value: BackupDiagnostic) -> String { switch value { case .present: L10n.text("value.backupPresent"); case .missing: L10n.text("value.backupMissing"); case .invalid: L10n.text("value.backupInvalid") } }
}

private struct CommunityBackground: View {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var drifting = false
    var body: some View {
        ZStack {
            WindowGlassView()
            if let url = Bundle.module.url(
                forResource: "CommunityBackground",
                withExtension: "jpg"
            ), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(reduceTransparency ? 0.13 : 0.90)
                    .clipped()
            }
            Rectangle()
                .fill(reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                    : AnyShapeStyle(.ultraThinMaterial))
                .opacity(reduceTransparency ? 1 : 0.42)
            Rectangle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.13) : Color.white.opacity(0.08))
            Circle().fill(.pink.opacity(0.055)).frame(width: 360).blur(radius: 86).offset(x: drifting ? 260 : 210, y: drifting ? -230 : -180)
        }.ignoresSafeArea().onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drifting = true }
        }
    }
}

private struct WindowGlassView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = ConfiguringVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private final class ConfiguringVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
    }
}

private struct DetailRow: View { let label: String; let value: String; var body: some View { HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled) } } }
private struct RiskRow: View { let symbol: String; let text: String; var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).foregroundStyle(.pink).frame(width: 24); Text(text).fixedSize(horizontal: false, vertical: true) } } }
private struct OnboardingRow: View { let symbol: String; let text: String; var body: some View { HStack(spacing: 14) { Image(systemName: symbol).font(.title2).foregroundStyle(.pink).frame(width: 30); Text(text); Spacer() }.padding(.horizontal, 12) } }
private extension View {
    func communityCard(solid: Bool) -> some View {
        padding(20).background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(solid ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial)).shadow(color: .black.opacity(0.06), radius: 18, y: 8) }.overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.18)) }
    }
}
