import SwiftUI
import Combine
import Foundation
import NaturalLanguage

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileItem]?
    var isExpanded: Bool
    var isExcluded: Bool
    var includeComments: Bool
    
    init(name: String, path: String, isDirectory: Bool, children: [FileItem]? = nil, isExpanded: Bool = false, isExcluded: Bool = false, includeComments: Bool = true) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
        self.isExcluded = isExcluded
        self.includeComments = includeComments
    }
    
    static func empty() -> FileItem {
        FileItem(name: "", path: "", isDirectory: false)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum OutputFormat: String, CaseIterable {
    case json
    case text
    case markdown
    case html
    case plainText
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .plainText: return "txt"
        }
    }
}

struct Config {
    var showHiddenFiles: Bool = false
    var includeImages: Bool = true
    var includeComments: Bool = true
    var includeDependencies: Bool = true
    var includeTests: Bool = true
    var outputFormat: OutputFormat = .markdown
}

@MainActor
class FileSystemModel: ObservableObject {
    struct Config {
        var showHiddenFiles: Bool = false
    }
    
    @Published var config = Config() {
        didSet {
            if oldValue.showHiddenFiles != config.showHiddenFiles {
                refreshDirectory(showHidden: config.showHiddenFiles)
            }
        }
    }
    
    @Published var fileItems: [FileItem] = []
    @Published var selectedFiles: Set<FileItem> = []
    @Published var savedSummaries: [SavedSummary] = []
    @Published var lastClickedFileName: String?
    @Published var lastClickedFilePath: String?
    @Published var lastClickedFileContent: String = ""
    @Published var fileImports: [String: Set<String>] = [:]
    @Published var fileExports: [String: Set<String>] = [:]
    @Published var showComments: Bool = true
    var rootPath: String?
    
    struct SavedSummary: Identifiable, Codable {
        var id: String
        let fileName: String
        let content: String
        var isIncluded: Bool
        let timestamp: Date
        
        init(id: String = UUID().uuidString, fileName: String, content: String, timestamp: Date = Date()) {
            self.id = id
            self.fileName = fileName
            self.content = content
            self.isIncluded = true
            self.timestamp = timestamp
        }
    }
    
    init() {
        self.config = Config()
        loadSavedSummaries()
    }
    
    func loadDirectory(at url: URL) {
        rootPath = url.path
        refreshDirectory(showHidden: config.showHiddenFiles)
    }
    
    private func updateImportsExports(for file: String, content: String) {
        let lines = content.components(separatedBy: .newlines)
        var imports = Set<String>()
        var exports = Set<String>()
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect imports
            if let importRange = trimmed.range(of: #"^import\s+([A-Za-z_][A-Za-z0-9_]*(\.\w+)*)"#, options: .regularExpression) {
                let module = String(trimmed[importRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                imports.insert(module)
            }
            
            // Detect exported symbols (public/Open declarations)
            if trimmed.hasPrefix("public ") || trimmed.hasPrefix("open ") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 2, let symbol = components.last {
                    exports.insert(symbol)
                }
            }
        }
        
        fileImports[file] = imports
        if fileExports[file] == nil {
            fileExports[file] = exports
        } else {
            fileExports[file]?.formUnion(exports)
        }
    }
    
    private func listDirectory(_ path: String, showHidden: Bool) -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for name in contents {
                // Skip hidden files if showHidden is false
                if !showHidden && name.hasPrefix(".") {
                    continue
                }
                
                let fullPath = (path as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                    let item = FileItem(
                        name: name,
                        path: fullPath,
                        isDirectory: isDirectory.boolValue,
                        children: isDirectory.boolValue ? listDirectory(fullPath, showHidden: showHidden) : nil,
                        isExpanded: false,
                        isExcluded: false,
                        includeComments: true
                    )
                    items.append(item)
                    
                    // Update imports/exports for code files
                    if !isDirectory.boolValue && name.hasSuffix(".swift") {
                        if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                            updateImportsExports(for: fullPath, content: content)
                        }
                    }
                }
            }
        } catch {
            print("Error reading directory: \(error)")
        }
        
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    func refreshDirectory(showHidden: Bool = false) {
        if let rootPath = rootPath {
            fileItems = listDirectory(rootPath, showHidden: showHidden)
        }
    }
    
    func toggleSelection(for item: FileItem) {
        if selectedFiles.contains(item) {
            selectedFiles.remove(item)
        } else {
            selectedFiles.insert(item)
        }
    }
    
    func handleFileClick(_ item: FileItem) {
        guard !item.isDirectory else { return }
        
        lastClickedFileName = item.path
        lastClickedFilePath = item.path
        if let content = try? String(contentsOfFile: item.path) {
            if item.includeComments {
                lastClickedFileContent = content
            } else {
                lastClickedFileContent = stripComments(from: content)
            }
            analyzeFileRelations(for: item.path)
        }
    }
    
    func analyzeFileRelations(for filePath: String) {
        guard let content = try? String(contentsOfFile: filePath) else { return }
        
        // Clear previous analysis for this file
        fileImports[filePath] = []
        fileExports[filePath] = []
        
        // Analyze imports in the current file
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                let module = trimmed.replacingOccurrences(of: "import ", with: "").trimmingCharacters(in: .whitespaces)
                fileImports[filePath, default: []].insert(module)
            }
        }
        
        // Analyze which files import this file
        guard let rootPath = rootPath else { return }
        
        // Get all Swift files in the project
        if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: rootPath),
                                                         includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift",
                      fileURL.path != filePath else { continue }
                
                if let otherContent = try? String(contentsOf: fileURL) {
                    let otherLines = otherContent.components(separatedBy: .newlines)
                    for line in otherLines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if let fileName = URL(fileURLWithPath: filePath).lastPathComponent.components(separatedBy: ".").first,
                           (trimmed.contains("import \(fileName)") || trimmed.contains("from: \(fileName)")) {
                            fileExports[filePath, default: []].insert(fileURL.path)
                        }
                    }
                }
            }
        }
    }
    
    func previewFileContent(for item: FileItem) {
        guard !item.isDirectory else { return }
        
        lastClickedFileName = item.path
        lastClickedFilePath = item.path
        if let content = try? String(contentsOfFile: item.path, encoding: .utf8) {
            lastClickedFileContent = content
            analyzeFileImportsAndExports(content, filePath: item.path)
        } else {
            lastClickedFileContent = "Unable to read file content"
        }
    }
    
    private func analyzeFileImportsAndExports(_ content: String, filePath: String) {
        // Clear existing entries for this file
        fileImports[filePath] = Set<String>()
        fileExports[filePath] = Set<String>()
        
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        let currentDir = (filePath as NSString).deletingLastPathComponent
        
        // First pass: collect all exports from all files
        if fileExports.isEmpty {
            for file in fileItems where !file.isDirectory {
                if let fileContent = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    collectExports(from: fileContent, filePath: file.path)
                }
            }
        }
        
        switch fileExtension {
        case "ts", "svelte", "js":
            analyzeJavaScriptLikeFile(content, filePath: filePath, currentDir: currentDir)
        case "swift":
            analyzeSwiftFile(content, filePath: filePath, currentDir: currentDir)
        default:
            break
        }
    }
    
    private func collectExports(from content: String, filePath: String) {
        let exportPatterns = [
            // JavaScript/TypeScript patterns
            "export\\s+(const|let|var|function|class|interface|type)\\s+([A-Za-z0-9_]+)",
            "export\\s+\\{([^}]+)\\}",
            "export\\s+default\\s+([A-Za-z0-9_]+)",
            // Swift patterns
            "public\\s+(class|struct|enum|protocol|func|var|let)\\s+([A-Za-z0-9_]+)",
            "public\\s+protocol\\s+([A-Za-z0-9_]+)",
            // General patterns
            "^\\s*(class|struct|enum|interface)\\s+([A-Za-z0-9_]+)"
        ]
        
        for pattern in exportPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                
                for match in matches {
                    let lastGroup = match.numberOfRanges - 1
                    if let exportRange = Range(match.range(at: lastGroup), in: content) {
                        let exports = String(content[exportRange])
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        
                        fileExports[filePath, default: Set()].formUnion(exports)
                    }
                }
            }
        }
    }
    
    private func analyzeJavaScriptLikeFile(_ content: String, filePath: String, currentDir: String) {
        // Analyze imports
        let importPatterns = [
            "import\\s*\\{([^}]+)\\}\\s*from\\s*['\"]([^'\"]+)['\"]",
            "import\\s+([A-Za-z0-9_]+)\\s+from\\s*['\"]([^'\"]+)['\"]",
            "import\\s*\\*\\s*as\\s+([A-Za-z0-9_]+)\\s+from\\s*['\"]([^'\"]+)['\"]",
            "require\\(['\"]([^'\"]+)['\"]\\)"
        ]
        
        for pattern in importPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                
                for match in matches {
                    if let importRange = Range(match.range(at: match.numberOfRanges - 1), in: content) {
                        let importPath = String(content[importRange])
                        
                        if importPath.hasPrefix(".") {
                            // Resolve relative path
                            let resolvedPath = (currentDir as NSString).appendingPathComponent(importPath)
                            let normalizedPath = (resolvedPath as NSString).standardizingPath
                            
                            // Try different extensions if the file doesn't exist
                            let extensions = ["", ".ts", ".js", ".svelte", ".swift"]
                            for ext in extensions {
                                let fullPath = normalizedPath + ext
                                if FileManager.default.fileExists(atPath: fullPath) {
                                    fileImports[filePath, default: Set()].insert(fullPath)
                                    break
                                }
                            }
                        } else {
                            fileImports[filePath, default: Set()].insert(importPath)
                        }
                    }
                }
            }
        }
    }
    
    private func analyzeSwiftFile(_ content: String, filePath: String, currentDir: String) {
        // Analyze imports
        let importPatterns = [
            "import\\s+([A-Za-z0-9_\\.]+)",
            "@testable\\s+import\\s+([A-Za-z0-9_\\.]+)"
        ]
        
        for pattern in importPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                
                for match in matches {
                    if let importRange = Range(match.range(at: 1), in: content) {
                        let importName = String(content[importRange])
                        fileImports[filePath, default: Set()].insert(importName)
                    }
                }
            }
        }
        
        // Analyze exports (public declarations)
        let exportPatterns = [
            "public\\s+(class|struct|enum|protocol|func|var|let)\\s+([A-Za-z0-9_]+)",
            "public\\s+protocol\\s+([A-Za-z0-9_]+)"
        ]
        
        for pattern in exportPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                
                for match in matches {
                    let lastGroup = match.numberOfRanges - 1
                    if let exportRange = Range(match.range(at: lastGroup), in: content) {
                        let exportName = String(content[exportRange])
                        fileExports[filePath, default: Set()].insert(exportName)
                    }
                }
            }
        }
    }
    
    func generateSummary(for fileURL: URL, content: String) async -> String {
        var analysis = ""
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // Basic file info
        analysis += "File Analysis:\n"
        analysis += "-------------\n"
        analysis += "File Type: \(fileExtension.uppercased())\n"
        analysis += "Location: \(fileURL.path)\n\n"
        
        // Code Purpose
        analysis += "Code Purpose:\n"
        analysis += "-------------\n"
        if let purpose = await analyzePurpose(content, fileExtension: fileExtension) {
            analysis += purpose + "\n\n"
        }
        
        // Dependencies
        analysis += "Dependencies:\n"
        analysis += "-------------\n"
        if let imports = fileImports[fileURL.path], !imports.isEmpty {
            for imp in imports.sorted() {
                analysis += "• \(imp)\n"
            }
        } else {
            analysis += "No external dependencies found\n"
        }
        analysis += "\n"
        
        // Exports
        analysis += "Public Interfaces:\n"
        analysis += "----------------\n"
        if let exports = fileExports[fileURL.path], !exports.isEmpty {
            for exp in exports.sorted() {
                analysis += "• \(exp)\n"
            }
        } else {
            analysis += "No public interfaces found\n"
        }
        analysis += "\n"
        
        // Code Structure
        analysis += "Code Structure:\n"
        analysis += "--------------\n"
        if let structure = await analyzeStructure(content, fileExtension: fileExtension) {
            analysis += structure + "\n\n"
        }
        
        return analysis
    }
    
    private func analyzePurpose(_ content: String, fileExtension: String) async -> String? {
        var purpose = ""
        
        // Check for file type specific patterns
        switch fileExtension {
        case "ts", "js", "svelte":
            if content.contains("React") || content.contains("Component") {
                purpose += "This is a React component that "
                if content.contains("useState") {
                    purpose += "manages state "
                }
                if content.contains("useEffect") {
                    purpose += "and handles side effects "
                }
            } else if content.contains("export default") {
                purpose += "This module exports functionality for "
            }
            
        case "swift":
            if content.contains("View") && content.contains("SwiftUI") {
                purpose += "This is a SwiftUI view that "
                if content.contains("@State") {
                    purpose += "manages internal state "
                }
                if content.contains("@Binding") {
                    purpose += "and receives external state updates "
                }
            } else if content.contains("class") || content.contains("struct") {
                purpose += "This is a data model that "
                if content.contains("Codable") {
                    purpose += "can be encoded/decoded "
                }
            }
            
        default:
            purpose += "This is a source file that "
        }
        
        // Look for common patterns
        if content.contains("fetch") || content.contains("request") || content.contains("URLSession") {
            purpose += "handles network requests "
        }
        if content.contains("save") || content.contains("update") || content.contains("delete") {
            purpose += "and manages data persistence "
        }
        if content.contains("calculate") || content.contains("compute") {
            purpose += "performs calculations "
        }
        
        return purpose.isEmpty ? nil : purpose.trimmingCharacters(in: .whitespaces) + "."
    }
    
    private func analyzeStructure(_ content: String, fileExtension: String) async -> String? {
        var structure = ""
        
        // Count functions
        let functionPattern = "func\\s+[A-Za-z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: functionPattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            structure += "Contains \(matches.count) function(s)\n"
        }
        
        // Check for classes/structs
        let typePattern = "(class|struct|enum)\\s+[A-Za-z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: typePattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            if matches.count > 0 {
                structure += "Defines \(matches.count) type(s)\n"
            }
        }
        
        // Check for comments
        let commentLines = content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .count
        if commentLines > 0 {
            structure += "Contains \(commentLines) comment line(s)\n"
        }
        
        return structure.isEmpty ? nil : structure
    }
    
    func saveSummary(_ content: String, for fileName: String) {
        let summary = SavedSummary(id: UUID().uuidString,
                                 fileName: fileName,
                                 content: content,
                                 timestamp: Date())
        
        // Update or add the summary
        if let index = savedSummaries.firstIndex(where: { $0.fileName == fileName }) {
            savedSummaries[index] = summary
        } else {
            savedSummaries.append(summary)
        }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(savedSummaries) {
            UserDefaults.standard.set(encoded, forKey: "SavedSummaries")
        }
    }
    
    func loadSavedSummaries() {
        if let data = UserDefaults.standard.data(forKey: "SavedSummaries"),
           let decoded = try? JSONDecoder().decode([SavedSummary].self, from: data) {
            savedSummaries = decoded
        }
    }
    
    func getSavedSummary(for fileName: String) -> String? {
        return savedSummaries.first(where: { $0.fileName == fileName })?.content
    }
    
    func generateExport(format: OutputFormat = .json) -> String {
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
        case .json:
            output += "{\"timestamp\": \"\(timestamp)\", \"files\": ["
        case .text:
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
        case .json:
            output += "\"fileTree\": \"\(generateFileTree(for: selectedFiles))\","
        case .text:
            output += "Selected Files:\n\n"
            output += generateFileTree(for: selectedFiles)
            output += "\n"
        }
        
        // Add file contents with comment settings respected
        switch format {
        case .markdown:
            output += "## File Contents\n\n"
            for file in selectedFiles where !file.isDirectory {
                output += "### \(file.name)\n\n"
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = showComments ? content : stripComments(from: content)
                    output += "```\n\(processedContent)\n```\n\n"
                }
            }
        case .html:
            output += "<h2>File Contents</h2>\n"
            for file in selectedFiles where !file.isDirectory {
                output += "<h3>\(file.name)</h3>\n<pre>\n"
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = showComments ? content : stripComments(from: content)
                    output += processedContent
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                }
                output += "</pre>\n"
            }
        case .plainText:
            output += "File Contents:\n\n"
            for file in selectedFiles where !file.isDirectory {
                output += "=== \(file.name) ===\n\n"
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = showComments ? content : stripComments(from: content)
                    output += "\(processedContent)\n\n"
                }
            }
        case .json:
            output += "\"files\": ["
            for file in selectedFiles where !file.isDirectory {
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = showComments ? content : stripComments(from: content)
                    output += "{\"name\": \"\(file.name)\", \"content\": \"\(processedContent)\"},"
                }
            }
            output = String(output.dropLast())
            output += "]"
        case .text:
            output += "File Contents:\n\n"
            for file in selectedFiles where !file.isDirectory {
                output += "=== \(file.name) ===\n\n"
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = showComments ? content : stripComments(from: content)
                    output += "\(processedContent)\n\n"
                }
            }
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
            case .json:
                output += "\"summaries\": ["
                for summary in includedSummaries {
                    output += "{\"name\": \"\(summary.fileName)\", \"content\": \"\(summary.content)\"},"
                }
                output = String(output.dropLast())
                output += "]"
            case .text:
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
        } else if format == .json {
            output += "}"
        }
        
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
    
    public func stripComments(from content: String) -> String {
        var result = content
        
        // Remove single-line comments
        let singleLinePattern = "\\/\\/.*$"
        if let regex = try? NSRegularExpression(pattern: singleLinePattern, options: .anchorsMatchLines) {
            result = regex.stringByReplacingMatches(in: result,
                                                  options: [],
                                                  range: NSRange(result.startIndex..., in: result),
                                                  withTemplate: "")
        }
        
        // Remove multi-line comments
        let multiLinePattern = "\\/\\*[\\s\\S]*?\\*\\/"
        if let regex = try? NSRegularExpression(pattern: multiLinePattern, options: []) {
            result = regex.stringByReplacingMatches(in: result,
                                                  options: [],
                                                  range: NSRange(result.startIndex..., in: result),
                                                  withTemplate: "")
        }
        
        // Remove empty lines and normalize spacing
        result = result.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
        
        return result
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