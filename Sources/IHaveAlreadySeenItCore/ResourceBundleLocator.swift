import Foundation

/// Locates SwiftPM resource bundles in both a packaged macOS App and a SwiftPM build tree.
///
/// Packaged Apps place resources under Contents/Resources, while SwiftPM executable builds
/// commonly place the generated bundle beside the executable. Missing optional UI resources
/// fall back to the caller's main bundle instead of trapping during application startup.
public enum ResourceBundleLocator {
    public static func candidateURLs(
        bundleName: String,
        mainResourceURL: URL?,
        bundleURL: URL?,
        executableURL: URL?
    ) -> [URL] {
        var candidates: [URL] = []
        if let mainResourceURL {
            candidates.append(mainResourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }
        if let bundleURL {
            candidates.append(bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        }
        if let executableURL {
            candidates.append(
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        var seen = Set<URL>()
        return candidates.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    public static func locate(
        bundleName: String,
        mainBundle: Bundle = .main,
        executableURL: URL? = CommandLine.arguments.first.map(URL.init(fileURLWithPath:))
    ) -> Bundle {
        let candidates = candidateURLs(
            bundleName: bundleName,
            mainResourceURL: mainBundle.resourceURL,
            bundleURL: mainBundle.bundleURL,
            executableURL: executableURL
        )
        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return mainBundle
    }
}
