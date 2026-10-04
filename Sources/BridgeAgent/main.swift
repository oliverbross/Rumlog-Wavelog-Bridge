import Foundation

private let version = "0.1.0-dev"

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] {
    print(version)
} else if arguments == ["doctor"] {
    let rumlogPath = "/Applications/RUMlogNG.app"
    let installed = FileManager.default.fileExists(atPath: rumlogPath)
    print("RUMlog–Wavelog Bridge \(version)")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("RUMlogNG: \(installed ? "found at \(rumlogPath)" : "not found")")
    print("Active peer emulation: disabled pending protocol discovery")
} else {
    print("""
    RUMlog–Wavelog Bridge \(version)

    The synchronization daemon is not enabled yet. Use `rumlog-probe` to capture
    disposable RUMlog peer traffic, or run `rumlog-wavelog-bridge doctor`.
    """)
}
