import Foundation

/// Logs transcriptions to a JSONL file for history tracking.
actor TranscriptionLogger {
    // MARK: - Types

    struct LogEntry: Codable {
        let timestamp: String // ISO 8601 format
        let rawText: String
        let cleanedText: String
        let wordCount: Int
        let duration: TimeInterval
        let wpm: Double
        let mode: String // "cloud", "local", or "off"
        let model: String // Model name or "none"
    }

    // MARK: - Singleton

    static let shared = TranscriptionLogger()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logFileURL: URL
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Initialization

    private init() {
        // Create log directory: ~/Library/Application Support/it.shek.dictator/
        // This location doesn't require special permissions
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dictatorDir = appSupportURL.appendingPathComponent("it.shek.dictator")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: dictatorDir, withIntermediateDirectories: true)

        // Log file path
        logFileURL = dictatorDir.appendingPathComponent("transcriptions.jsonl")

        print("[TranscriptionLogger] Initialized - Log file: \(logFileURL.path)")
    }

    // MARK: - Public Methods

    /// Log a transcription to the JSONL file.
    func log(
        rawText: String,
        cleanedText: String,
        wordCount: Int,
        duration: TimeInterval,
        wpm: Double,
        mode: String,
        model: String
    ) {
        let entry = LogEntry(
            timestamp: Self.dateFormatter.string(from: Date()),
            rawText: rawText,
            cleanedText: cleanedText,
            wordCount: wordCount,
            duration: duration,
            wpm: wpm,
            mode: mode,
            model: model
        )

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(entry)
            guard let jsonLine = String(data: jsonData, encoding: .utf8) else {
                print("[TranscriptionLogger] Failed to encode JSON to string")
                return
            }

            // Append to file (create if doesn't exist)
            let lineWithNewline = jsonLine + "\n"
            if let data = lineWithNewline.data(using: .utf8) {
                if fileManager.fileExists(atPath: logFileURL.path) {
                    // Append to existing file
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try fileHandle.close()
                } else {
                    // Create new file
                    try data.write(to: logFileURL, options: .atomic)
                }

                print("[TranscriptionLogger] Logged: \(wordCount) words, \(String(format: "%.1f", wpm)) WPM, mode: \(mode)")
            }
        } catch {
            print("[TranscriptionLogger] Failed to log transcription: \(error)")
        }
    }

    /// Read all log entries from the file.
    func readAllEntries() -> [LogEntry] {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            print("[TranscriptionLogger] Log file doesn't exist yet")
            return []
        }

        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }

            let decoder = JSONDecoder()
            let entries = lines.compactMap { line -> LogEntry? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: data)
            }

            print("[TranscriptionLogger] Read \(entries.count) entries from log")
            return entries
        } catch {
            print("[TranscriptionLogger] Failed to read log file: \(error)")
            return []
        }
    }

    /// Get the most recent N entries.
    func recentEntries(limit: Int = 100) -> [LogEntry] {
        let all = readAllEntries()
        return Array(all.suffix(limit).reversed()) // Most recent first
    }

    /// Get log file path.
    nonisolated var logFilePath: String {
        logFileURL.path
    }
}
