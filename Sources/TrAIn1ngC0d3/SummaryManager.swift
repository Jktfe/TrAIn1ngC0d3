import Foundation

class SummaryManager {
    static let shared = SummaryManager()
    private let fileManager = FileManager.default
    
    private var summariesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let summariesDir = appSupport.appendingPathComponent("TrAIn1ngC0d3/Summaries", isDirectory: true)
        try? fileManager.createDirectory(at: summariesDir, withIntermediateDirectories: true)
        return summariesDir
    }
    
    func saveSummary(_ summary: String, forProject project: String) throws {
        let projectDir = summariesDirectory.appendingPathComponent(project, isDirectory: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "summary_\(timestamp).md"
        let fileURL = projectDir.appendingPathComponent(filename)
        
        try summary.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func getSummaries(forProject project: String) throws -> [(date: Date, content: String)] {
        let projectDir = summariesDirectory.appendingPathComponent(project)
        guard fileManager.fileExists(atPath: projectDir.path) else { return [] }
        
        let files = try fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
        return try files.compactMap { url in
            guard url.lastPathComponent.hasPrefix("summary_") else { return nil }
            let content = try String(contentsOf: url, encoding: .utf8)
            let dateStr = url.lastPathComponent.replacingOccurrences(of: "summary_", with: "")
                .replacingOccurrences(of: ".md", with: "")
            if let date = ISO8601DateFormatter().date(from: dateStr) {
                return (date, content)
            }
            return nil
        }.sorted { $0.date > $1.date }
    }
}
