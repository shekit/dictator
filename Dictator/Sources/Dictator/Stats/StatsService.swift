import Foundation

/// Tracks usage statistics for transcriptions.
/// Handles word count, WPM calculation, and daily aggregation.
@MainActor
final class StatsService: ObservableObject {
    // MARK: - Types

    struct DailyStats: Codable {
        let date: String // YYYY-MM-DD format
        var totalWords: Int
        var totalDuration: TimeInterval // in seconds
        var recordingCount: Int

        var averageWPM: Double {
            guard totalDuration > 0 else { return 0 }
            return (Double(totalWords) / totalDuration) * 60.0
        }
    }

    struct TranscriptionStats {
        let wordCount: Int
        let wpm: Double
        let duration: TimeInterval
    }

    // MARK: - Singleton

    static let shared = StatsService()

    // MARK: - Published Properties

    @Published private(set) var todayStats: DailyStats
    @Published private(set) var allTimeStats: [DailyStats] = []

    // MARK: - Properties

    private let userDefaults = UserDefaults.standard
    private let statsKey = "dictator.stats.daily"
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Initialization

    private init() {
        // Get today's date first
        let todayDate = Self.dateFormatter.string(from: Date())

        // Load persisted stats
        let loadedStats: [DailyStats]
        if let data = userDefaults.data(forKey: statsKey),
           let stats = try? JSONDecoder().decode([DailyStats].self, from: data) {
            loadedStats = stats
        } else {
            loadedStats = []
        }

        // Initialize today's stats (required before accessing allTimeStats)
        if let existing = loadedStats.first(where: { $0.date == todayDate }) {
            todayStats = existing
        } else {
            todayStats = DailyStats(date: todayDate, totalWords: 0, totalDuration: 0, recordingCount: 0)
        }

        // Now we can initialize allTimeStats
        allTimeStats = loadedStats

        print("[StatsService] Initialized - Today: \(todayStats.totalWords) words, \(todayStats.recordingCount) recordings")
    }

    // MARK: - Public Methods

    /// Calculate word count from text.
    func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        // Split by whitespace and filter empty strings
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    /// Calculate WPM (words per minute) from word count and duration.
    func calculateWPM(wordCount: Int, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return (Double(wordCount) / duration) * 60.0
    }

    /// Record a new transcription and update stats.
    /// Returns the stats for this transcription.
    func recordTranscription(text: String, duration: TimeInterval) -> TranscriptionStats {
        let words = wordCount(text)
        let wpm = calculateWPM(wordCount: words, duration: duration)

        // Check if we need to roll over to a new day
        let todayDate = Self.dateFormatter.string(from: Date())
        if todayStats.date != todayDate {
            // Save current day's stats
            saveCurrentDay()

            // Start new day
            todayStats = DailyStats(date: todayDate, totalWords: 0, totalDuration: 0, recordingCount: 0)
        }

        // Update today's stats
        todayStats.totalWords += words
        todayStats.totalDuration += duration
        todayStats.recordingCount += 1

        // Save to persistence
        saveCurrentDay()

        print("[StatsService] Recorded: \(words) words, \(String(format: "%.1f", wpm)) WPM, duration: \(String(format: "%.2f", duration))s")
        print("[StatsService] Today totals: \(todayStats.totalWords) words, \(todayStats.recordingCount) recordings")

        return TranscriptionStats(wordCount: words, wpm: wpm, duration: duration)
    }

    /// Get total stats for a specific date.
    func stats(for date: Date) -> DailyStats? {
        let dateString = Self.dateFormatter.string(from: date)
        return allTimeStats.first { $0.date == dateString }
    }

    /// Get total words across all time.
    var totalWordsAllTime: Int {
        allTimeStats.reduce(0) { $0 + $1.totalWords }
    }

    /// Get total recordings across all time.
    var totalRecordingsAllTime: Int {
        allTimeStats.reduce(0) { $0 + $1.recordingCount }
    }

    /// Get average WPM across all time.
    var averageWPMAllTime: Double {
        let totalWords = allTimeStats.reduce(0) { $0 + $1.totalWords }
        let totalDuration = allTimeStats.reduce(0.0) { $0 + $1.totalDuration }
        guard totalDuration > 0 else { return 0 }
        return (Double(totalWords) / totalDuration) * 60.0
    }

    /// Get stats for the current week (last 7 days).
    func weekStats() -> (words: Int, recordings: Int, averageWPM: Double) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!

        let weeklyStats = allTimeStats.filter { stat in
            guard let statDate = Self.dateFormatter.date(from: stat.date) else { return false }
            return statDate >= weekAgo && statDate <= today
        }

        let totalWords = weeklyStats.reduce(0) { $0 + $1.totalWords }
        let totalRecordings = weeklyStats.reduce(0) { $0 + $1.recordingCount }
        let totalDuration = weeklyStats.reduce(0.0) { $0 + $1.totalDuration }
        let avgWPM = totalDuration > 0 ? (Double(totalWords) / totalDuration) * 60.0 : 0

        return (totalWords, totalRecordings, avgWPM)
    }

    // MARK: - Private Methods

    private func saveCurrentDay() {
        // Update or append today's stats
        if let index = allTimeStats.firstIndex(where: { $0.date == todayStats.date }) {
            allTimeStats[index] = todayStats
        } else {
            allTimeStats.append(todayStats)
        }

        // Keep only last 365 days to prevent unbounded growth
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -365, to: Date())!
        let cutoffString = Self.dateFormatter.string(from: cutoffDate)
        allTimeStats = allTimeStats.filter { $0.date >= cutoffString }

        // Persist to UserDefaults
        if let data = try? JSONEncoder().encode(allTimeStats) {
            userDefaults.set(data, forKey: statsKey)
        }
    }
}
