import Darwin
import IHaveAlreadySeenItTestSuite
import Testing

@main
enum TestRunner {
    static func main() async {
        guard TestSuiteMarker.isLinked else { exit(1) }
        let result: CInt = await Testing.__swiftPMEntryPoint()
        exit(result)
    }
}
