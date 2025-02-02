import SwiftUI
import Combine
import Foundation
import NaturalLanguage
import CreateML

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let isExcluded: Bool
    let children: [FileItem]?
    
    init(name: String, path: String, isDirectory: Bool, isExcluded: Bool = false, children: [FileItem]? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isExcluded = isExcluded
        self.children = children
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

@MainActor
class FileSystemModel: ObservableObject {
    @Published var fileItems: [FileItem] = []
    @Published var selectedFiles: Set<FileItem> = []
    @Published var savedSummaries: [SavedSummary] = []
    @Published var lastClickedFileName: String = ""
    @Published var lastClickedFileContent: String = ""
    @Published var importedFiles: [URL] = []
    @Published var exportedFiles: [URL] = []
    @Published var config: ExportConfig
    var rootPath: String?
    
    struct SavedSummary: Identifiable, Codable {
        var id: UUID
        let fileName: String
        let content: String
        var isIncluded: Bool
        
        init(fileName: String, content: String) {
            self.id = UUID()
            self.fileName = fileName
            self.content = content
            self.isIncluded = true
        }
    }
    
    init(config: ExportConfig = ExportConfig()) {
        self.config = config
    }
    
    func loadDirectory(at url: URL) {
        rootPath = url.path
        refreshFileList()
    }
    
    func refreshFileList() {
        guard let rootPath = rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)
        fileItems = loadFileItems(from: rootURL)
    }
    
    private func loadFileItems(from url: URL) -> [FileItem] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [URLResourceKey.isDirectoryKey],
            options: config.showHiddenFiles ? [] : .skipsHiddenFiles
        ) else {
            return []
        }
        
        return contents.compactMap { url -> FileItem? in
            let isDirectory = (try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            let path = url.path
            
            let children = isDirectory ? loadFileItems(from: url) : nil
            return FileItem(
                name: name,
                path: path,
                isDirectory: isDirectory,
                isExcluded: !config.showHiddenFiles && name.hasPrefix("."),
                children: children
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    func toggleSelection(for item: FileItem) {
        if selectedFiles.contains(item) {
            selectedFiles.remove(item)
        } else {
            selectedFiles.insert(item)
        }
    }
    
    func previewFileContent(for item: FileItem) {
        guard !item.isDirectory else { return }
        lastClickedFileName = item.name
        lastClickedFileContent = (try? String(contentsOfFile: item.path)) ?? ""
    }
    
    func generateSummary(for content: String) async -> String {
        // Try Apple's NL processing first
        if let appleSummary = generateAppleSummary(for: content) {
            return appleSummary
        }
        
        // Fallback to local DeepSeek if available
        return await generateDeepSeekSummary(for: content)
    }
    
    private func generateAppleSummary(for content: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.tokenType, .language, .lexicalClass])
        tagger.string = content
        
        // Get key sentences
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        var sentences: [String] = []
        tagger.enumerateTags(in: content.startIndex..<content.endIndex, unit: .sentence, scheme: .tokenType, options: options) { _, range in
            let sentence = String(content[range])
            sentences.append(sentence)
            return true
        }
        
        // Select important sentences (first, last, and any containing key terms)
        var summary = ""
        if let first = sentences.first {
            summary += first + "\n\n"
        }
        
        let keyTerms = ["important", "key", "main", "significant", "essential", "critical"]
        let middleSentences = sentences.dropFirst().dropLast()
        for sentence in middleSentences {
            if keyTerms.contains(where: { sentence.lowercased().contains($0) }) {
                summary += sentence + "\n\n"
            }
        }
        
        if let last = sentences.last, last != sentences.first {
            summary += last
        }
        
        return summary.isEmpty ? nil : summary
    }
    
    private func generateDeepSeekSummary(for content: String) async -> String {
        // Here you would integrate with your local DeepSeek instance
        // For now, return a placeholder
        return "Summary generation with DeepSeek is not yet implemented.\n\nOriginal content:\n\n\(content)"
    }
    
    func saveSummary(_ content: String, for fileName: String) {
        let summary = SavedSummary(fileName: fileName, content: content)
        savedSummaries.append(summary)
    }
    
    func toggleSummary(_ summary: SavedSummary) {
        if let index = savedSummaries.firstIndex(where: { $0.id == summary.id }) {
            savedSummaries[index].isIncluded.toggle()
        }
    }
    
    func importFiles(from urls: [URL]) {
        importedFiles.append(contentsOf: urls)
        for url in urls {
            if (try? String(contentsOf: url)) != nil {
                let item = FileItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    isDirectory: false,
                    isExcluded: false
                )
                selectedFiles.insert(item)
            }
        }
    }
    
    func generateExport(format: ExportConfig.OutputFormat) -> String {
        var output = ""
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Add header
        switch format {
        case .markdown:
            output += "# Export \(timestamp)\n\n"
        case .html:
            output += """
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Export \(timestamp)</title>
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                        pre { background: #f5f5f5; padding: 1em; border-radius: 4px; }
                    </style>
                </head>
                <body>
                <h1>Export \(timestamp)</h1>
                
                """
        case .plainText:
            output += "Export \(timestamp)\n\n"
        }
        
        // Add file tree
        switch format {
        case .markdown:
            output += "## Selected Files\n\n"
            output += generateFileTree(for: selectedFiles)
            output += "\n"
        case .html:
            output += "<h2>Selected Files</h2>\n<pre>\n"
            output += generateFileTree(for: selectedFiles)
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            output += "</pre>\n"
        case .plainText:
            output += "Selected Files:\n\n"
            output += generateFileTree(for: selectedFiles)
            output += "\n"
        }
        
        // Add summaries
        let includedSummaries = savedSummaries.filter { $0.isIncluded }
        if !includedSummaries.isEmpty {
            switch format {
            case .markdown:
                output += "## Summaries\n\n"
                for summary in includedSummaries {
                    output += "### \(summary.fileName)\n\n"
                    output += summary.content
                    output += "\n\n"
                }
            case .html:
                output += "<h2>Summaries</h2>\n"
                for summary in includedSummaries {
                    output += "<h3>\(summary.fileName)</h3>\n"
                    output += "<div class='summary'>\n"
                    output += summary.content
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\n", with: "<br>\n")
                    output += "</div>\n"
                }
            case .plainText:
                output += "Summaries:\n\n"
                for summary in includedSummaries {
                    output += "=== \(summary.fileName) ===\n\n"
                    output += summary.content
                    output += "\n\n"
                }
            }
        }
        
        if format == .html {
            output += "</body></html>"
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "export-\(timestamp).\(format == .html ? "html" : "md")"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try? output.write(to: fileURL, atomically: true, encoding: .utf8)
        exportedFiles.append(fileURL)
        
        return output
    }
    
    private func generateFileTree(for items: Set<FileItem>) -> String {
        let sortedItems = items.sorted { $0.name < $1.name }
        return sortedItems.map { item in
            var output = "- \(item.name)\n"
            if item.isDirectory, let children = item.children {
                let childItems = Set(children)
                output += childItems.map { "  \($0.name)" }.joined(separator: "\n")
                output += "\n"
            }
            return output
        }
        .joined()
    }
    
    func getFolderSummary(for item: FileItem) -> String {
        var summary = ""
        
        // Basic information
        summary += "# Folder Summary: \(item.name)\n\n"
        
        // Count files and subdirectories
        var fileCount = 0
        var dirCount = 0
        var totalSize: Int64 = 0
        
        func processItem(_ item: FileItem) {
            if item.isDirectory {
                dirCount += 1
                if let children = item.children {
                    children.forEach(processItem)
                }
            } else {
                fileCount += 1
                if let attributes = try? FileManager.default.attributesOfItem(atPath: item.path) {
                    totalSize += attributes[.size] as? Int64 ?? 0
                }
            }
        }
        
        processItem(item)
        
        // Format size
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: totalSize)
        
        summary += """
            ## Statistics
            - Total Files: \(fileCount)
            - Total Subdirectories: \(dirCount)
            - Total Size: \(sizeString)
            
            """
        
        return summary
    }
}