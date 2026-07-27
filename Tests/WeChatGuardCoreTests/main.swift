import Foundation

do {
    try runVersionTests()
    try runCompatibilityTests()
    try runMachOEditorTests()
    try runApplicationInspectorTests()
    try runPatchPlannerTests()
    print("All WeChatGuard tests passed")
} catch {
    fputs("Test suite failed: \(error)\n", stderr)
    exit(1)
}
