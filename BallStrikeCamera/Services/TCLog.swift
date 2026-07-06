import os

/// Structured logging for TrueCarry. Use instead of print(): messages get
/// levels, categories, and show up filterable in Console.app / sysdiagnose
/// instead of vanishing in release builds.
///
///     TCLog.live.info("paired code=\(code, privacy: .public)")
///     TCLog.ble.error("hub disconnected: \(error.localizedDescription)")
enum TCLog {
    private static let subsystem = "com.truecarry.app"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let live = Logger(subsystem: subsystem, category: "livesim")
    static let ble = Logger(subsystem: subsystem, category: "ble")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
