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
    @Published var lastClickedFileName: String = ""
    @Published var lastClickedFileContent: String = ""
    @Published var fileImports: [String: Set<String>] = [:]
    @Published var fileExports: [String: Set<String>] = [:]
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
    
    init() {
        self.config = Config()
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
        fileExports[file] = exports
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
        lastClickedFileName = item.name
        if let content = try? String(contentsOfFile: item.path) {
            if item.includeComments {
                lastClickedFileContent = content
            } else {
                lastClickedFileContent = stripComments(from: content)
            }
        }
    }
    
    func generateSummary(for url: URL, content: String) async -> String {
        var summary = ""
        
        // Start with the main purpose
        summary += "Code Purpose:\n"
        
        // Get the main type declarations to understand what we're looking at
        let mainTypes = content.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || 
                       trimmed.hasPrefix("enum ") || trimmed.hasPrefix("protocol ")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Get functions to understand capabilities
        let functions = content.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("func ") || trimmed.hasPrefix("private func ") || 
                       trimmed.hasPrefix("public func ") || trimmed.hasPrefix("internal func ")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Get properties to understand state
        let properties = content.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return (trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ")) && 
                       !trimmed.contains("init(") && !trimmed.contains(" = {")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Determine the high-level purpose based on content analysis
        if content.contains("View") && content.contains("import SwiftUI") {
            summary += "This is a SwiftUI view that "
            
            if mainTypes.contains(where: { $0.contains("NavigationView") }) || functions.contains(where: { $0.contains("navigate") }) {
                summary += "handles navigation between different screens. "
            }
            
            if properties.contains(where: { $0.contains("@State") || $0.contains("@Binding") }) {
                summary += "manages user interface state. "
            }
            
            if properties.contains(where: { $0.contains("@ObservedObject") || $0.contains("@StateObject") }) {
                summary += "observes and reacts to data model changes. "
            }
            
            // Describe what the view displays
            if content.contains("List") {
                summary += "It displays a list of items"
                if let itemType = properties.first(where: { $0.contains("items:") || $0.contains("Array<") })?.components(separatedBy: ":").last {
                    summary += " of type \(itemType.trimmingCharacters(in: .whitespaces))"
                }
                summary += ". "
            } else if content.contains("Form") {
                summary += "It presents a form for user input. "
            } else if content.contains("TabView") {
                summary += "It organizes content in tabs. "
            }
            
            // Describe user interactions
            if functions.contains(where: { $0.contains("tap") || $0.contains("click") || $0.contains("select") }) {
                summary += "Users can interact with elements through taps/clicks. "
            }
            
            if functions.contains(where: { $0.contains("save") || $0.contains("update") || $0.contains("delete") }) {
                summary += "It allows users to modify data. "
            }
            
        } else if content.contains("ViewModel") || content.contains("ObservableObject") {
            summary += "This is a ViewModel that "
            
            // Describe what kind of data it manages
            let publishedProperties = properties.filter { $0.contains("@Published") }
            if !publishedProperties.isEmpty {
                summary += "manages and publishes changes to: "
                for prop in publishedProperties.prefix(3) {
                    if let propName = prop.components(separatedBy: "=").first?.components(separatedBy: " ").last {
                        summary += "\(propName), "
                    }
                }
                summary = String(summary.dropLast(2)) + ". "
            }
            
            // Describe its responsibilities
            if functions.contains(where: { $0.contains("fetch") || $0.contains("load") }) {
                summary += "It loads data from external sources. "
            }
            if functions.contains(where: { $0.contains("save") || $0.contains("update") }) {
                summary += "It handles data persistence. "
            }
            if functions.contains(where: { $0.contains("validate") || $0.contains("check") }) {
                summary += "It performs data validation. "
            }
            
        } else if mainTypes.contains(where: { $0.contains("Model") }) {
            summary += "This is a data model that "
            
            if content.contains("Codable") {
                summary += "can be encoded/decoded for data persistence. "
            }
            
            // Describe what it models
            let properties = properties.filter { !$0.contains("private") }
            if !properties.isEmpty {
                summary += "It represents an entity with properties like: "
                for prop in properties.prefix(3) {
                    if let propName = prop.components(separatedBy: ":").first?.components(separatedBy: " ").last {
                        summary += "\(propName), "
                    }
                }
                summary = String(summary.dropLast(2)) + ". "
            }
            
        } else if content.contains("extension ") {
            summary += "This file extends existing types with additional functionality. "
            
            // List what's being extended
            let extensions = content.components(separatedBy: .newlines)
                .filter { $0.contains("extension ") }
                .map { $0.replacingOccurrences(of: "extension ", with: "").trimmingCharacters(in: .whitespaces) }
            
            if !extensions.isEmpty {
                summary += "It adds capabilities to: "
                summary += extensions.joined(separator: ", ") + ". "
            }
            
            // Describe what capabilities are added
            if !functions.isEmpty {
                summary += "New functions include: "
                for function in functions.prefix(3) {
                    if let funcName = function.components(separatedBy: "(").first?.components(separatedBy: " ").last {
                        summary += "\(funcName), "
                    }
                }
                summary = String(summary.dropLast(2)) + ". "
            }
        }
        
        summary += "\n\n"
        
        // Add imports analysis
        if let imports = fileImports[url.path] {
            summary += "Dependencies:\n"
            for imp in imports {
                summary += "- \(imp)\n"
            }
            summary += "\n"
        }
        
        // Add exports analysis
        if let exports = fileExports[url.path] {
            summary += "Public Interfaces:\n"
            for exp in exports {
                summary += "- \(exp)\n"
            }
            summary += "\n"
        }
        
        // Add language-specific analysis
        let fileExtension = url.pathExtension.lowercased()
        summary += await analyzeLanguageSpecific(content: content, fileExtension: fileExtension)
        
        return summary
    }
    
    private func analyzeLanguageSpecific(content: String, fileExtension: String) async -> String {
        var analysis = ""
        
        // Language-specific analysis
        switch fileExtension {
        case "swift":
            analysis += await analyzeSwift(content)
        case "sql":
            analysis += await analyzeSQL(content)
        case "js", "ts", "jsx", "tsx":
            analysis += await analyzeJavaScript(content)
        case "dockerfile":
            analysis += await analyzeDockerfile(content)
        case "py":
            analysis += await analyzePython(content)
        default:
            // For unknown file types, use general NLP analysis
            analysis += await analyzeWithNLP(content)
        }
        
        // Add code complexity metrics for all files
        analysis += await analyzeComplexity(content)
        
        // Add NLP analysis for all files except Dockerfile
        if fileExtension != "dockerfile" {
            analysis += await analyzeWithNLP(content)
        }
        
        return analysis
    }
    
    private func analyzeWithNLP(_ content: String) async -> String {
        var analysis = "\nAdvanced Code Analysis:\n"
        
        // Initialize NLP components with expanded schemes
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .lemma, .language, .script])
        tagger.string = content
        
        // 1. Enhanced Comment Analysis
        let commentAnalysis = await analyzeComments(content)
        analysis += commentAnalysis
        
        // 2. Code Quality Metrics
        analysis += await analyzeCodeQualityMetrics(content)
        
        // 3. Semantic Code Analysis
        let semanticAnalysis = await analyzeSemantics(content, tagger: tagger)
        analysis += semanticAnalysis
        
        return analysis
    }
    
    private func analyzeCodeQualityMetrics(_ content: String) async -> String {
        var analysis = "\nCode Quality Metrics:\n"
        
        // Naming Convention Analysis
        var camelCaseCount = 0
        var snakeCaseCount = 0
        var pascalCaseCount = 0
        
        let camelCasePattern = try? NSRegularExpression(pattern: "^[a-z][a-zA-Z0-9]*$")
        let snakeCasePattern = try? NSRegularExpression(pattern: "^[a-z][a-z0-9_]*$")
        let pascalCasePattern = try? NSRegularExpression(pattern: "^[A-Z][a-zA-Z0-9]*$")
        
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let range = NSRange(location: 0, length: word.utf16.count)
            
            if camelCasePattern?.firstMatch(in: word, range: range) != nil {
                camelCaseCount += 1
            }
            if snakeCasePattern?.firstMatch(in: word, range: range) != nil {
                snakeCaseCount += 1
            }
            if pascalCasePattern?.firstMatch(in: word, range: range) != nil {
                pascalCaseCount += 1
            }
        }
        
        let total = Double(camelCaseCount + snakeCaseCount + pascalCaseCount)
        if total > 0 {
            let camelPercent = Int(Double(camelCaseCount) / total * 100)
            let snakePercent = Int(Double(snakeCaseCount) / total * 100)
            let pascalPercent = Int(Double(pascalCaseCount) / total * 100)
            
            analysis += "Naming Conventions:\n"
            analysis += "- camelCase: \(camelPercent)%\n"
            analysis += "- snake_case: \(snakePercent)%\n"
            analysis += "- PascalCase: \(pascalPercent)%\n"
            
            if max(camelPercent, snakePercent, pascalPercent) < 60 {
                analysis += "Warning: Inconsistent naming conventions\n"
            }
        }
        
        return analysis
    }
    
    private func analyzeJavaScript(_ content: String) async -> String {
        var analysis = "\nJavaScript Analysis:\n"
        
        // Check for React usage
        if content.contains("import React") || content.contains("from 'react'") {
            analysis += "- Uses React framework\n"
            if content.contains("useState") || content.contains("useEffect") {
                analysis += "  - Implements React Hooks\n"
            }
            if content.contains("useContext") {
                analysis += "  - Uses Context API for state management\n"
            }
        }
        
        // Check for modern JS features
        if content.contains("async") && content.contains("await") {
            analysis += "- Uses async/await for asynchronous operations\n"
        }
        if content.contains("class") && content.contains("extends") {
            analysis += "- Uses ES6+ class inheritance\n"
        }
        if content.contains("=>") {
            analysis += "- Uses arrow functions\n"
        }
        
        return analysis
    }
    
    private func analyzePython(_ content: String) async -> String {
        var analysis = "\nPython Analysis:\n"
        
        // Check for data science libraries
        if content.contains("import pandas") || content.contains("import numpy") {
            analysis += "- Uses data science libraries\n"
            if content.contains("DataFrame") {
                analysis += "  - Implements pandas DataFrames\n"
            }
            if content.contains("np.array") {
                analysis += "  - Uses NumPy arrays\n"
            }
        }
        
        // Check for async features
        if content.contains("async def") {
            analysis += "- Uses async/await for asynchronous operations\n"
        }
        
        // Check for type hints
        if content.contains(": ") && content.contains(" ->") {
            analysis += "- Uses type hints\n"
        }
        
        return analysis
    }
    
    private func analyzeSwift(_ content: String) async -> String {
        var analysis = "\nSwift Analysis:\n"
        let lines = content.components(separatedBy: .newlines)
        
        // Modern Swift Features
        analysis += "\nModern Swift Features:\n"
        
        // Property Wrappers
        if content.contains("@propertyWrapper") {
            analysis += "- Uses Property Wrappers:\n"
            for line in lines where line.contains("@propertyWrapper") {
                if let name = line.components(separatedBy: "struct ").last?.components(separatedBy: ":").first {
                    analysis += "  - \(name.trimmingCharacters(in: .whitespaces))\n"
                }
            }
        }
        
        // Result Builders
        if content.contains("@resultBuilder") {
            analysis += "- Uses Result Builders:\n"
            for line in lines where line.contains("@resultBuilder") {
                if let name = line.components(separatedBy: "struct ").last?.components(separatedBy: ":").first {
                    analysis += "  - \(name.trimmingCharacters(in: .whitespaces))\n"
                }
            }
        }
        
        // Async/Await
        var hasAsync = false
        if content.contains("async") {
            hasAsync = true
            analysis += "- Uses Async/Await Pattern\n"
            if content.contains("AsyncSequence") {
                analysis += "  - Implements AsyncSequence\n"
            }
            if content.contains("withTaskGroup") || content.contains("withThrowingTaskGroup") {
                analysis += "  - Uses Task Groups for concurrency\n"
            }
        }
        
        // Actors
        if content.contains("actor ") {
            analysis += "- Uses Actor Model for concurrency\n"
            if content.contains("nonisolated") {
                analysis += "  - Uses nonisolated members\n"
            }
            if content.contains("@MainActor") {
                analysis += "  - Uses MainActor isolation\n"
            }
        }
        
        // SwiftUI Integration
        analysis += "\nSwiftUI Features:\n"
        
        let swiftUIFeatures: [(pattern: String, description: String)] = [
            ("@State ", "State Management"),
            ("@Binding", "Binding Properties"),
            ("@ObservedObject", "Observable Objects"),
            ("@StateObject", "State Objects"),
            ("@EnvironmentObject", "Environment Objects"),
            ("@Environment", "Environment Values"),
            ("@ViewBuilder", "Custom View Builders"),
            ("@FetchRequest", "Core Data Integration"),
            ("GeometryReader", "Dynamic Layout"),
            ("PreferenceKey", "View Preferences")
        ]
        
        var usedFeatures = false
        for (pattern, description) in swiftUIFeatures {
            if content.contains(pattern) {
                if !usedFeatures {
                    usedFeatures = true
                }
                analysis += "- \(description)\n"
            }
        }
        
        if !usedFeatures {
            analysis += "- No SwiftUI features detected\n"
        }
        
        // Combine Framework
        analysis += "\nCombine Framework Usage:\n"
        
        let combineFeatures: [(pattern: String, description: String)] = [
            ("Publisher", "Publishers"),
            ("Subscriber", "Subscribers"),
            ("Subject", "Subjects"),
            ("CurrentValueSubject", "Current Value Subjects"),
            ("PassthroughSubject", "Passthrough Subjects"),
            ("sink", "Sink Subscribers"),
            ("assign", "Property Assignment"),
            ("map", "Value Transformation"),
            ("flatMap", "Publisher Transformation"),
            ("combineLatest", "Multiple Publisher Combination"),
            ("merge", "Publisher Merging"),
            ("debounce", "Value Debouncing"),
            ("throttle", "Value Throttling")
        ]
        
        var usesCombine = false
        for (pattern, description) in combineFeatures {
            if content.contains(pattern) {
                if !usesCombine {
                    usesCombine = true
                }
                analysis += "- \(description)\n"
            }
        }
        
        if !usesCombine {
            analysis += "- No Combine framework usage detected\n"
        }
        
        // Swift Concurrency
        if hasAsync {
            analysis += "\nConcurrency Patterns:\n"
            
            let concurrencyFeatures: [(pattern: String, description: String)] = [
                ("Task {", "Task Creation"),
                ("Task.detached", "Detached Tasks"),
                ("await", "Async/Await"),
                ("async let", "Concurrent Let Bindings"),
                ("withTaskGroup", "Task Groups"),
                ("withThrowingTaskGroup", "Error Handling Task Groups"),
                ("@MainActor", "Main Actor Isolation"),
                ("actor ", "Actor Types"),
                ("AsyncSequence", "Async Sequences"),
                ("AsyncStream", "Async Streams")
            ]
            
            for (pattern, description) in concurrencyFeatures {
                if content.contains(pattern) {
                    analysis += "- \(description)\n"
                }
            }
        }
        
        // Protocol Conformance
        analysis += "\nProtocol Conformance:\n"
        let commonProtocols = [
            "Codable", "Hashable", "Equatable", "Comparable", "Identifiable",
            "CustomStringConvertible", "CaseIterable", "RawRepresentable"
        ]
        
        var foundProtocols = false
        for proto in commonProtocols {
            if content.contains(proto) {
                if !foundProtocols {
                    foundProtocols = true
                }
                analysis += "- Conforms to \(proto)\n"
            }
        }
        
        if !foundProtocols {
            analysis += "- No common protocol conformance detected\n"
        }
        
        // Memory Management
        analysis += "\nMemory Management:\n"
        
        if content.contains("weak ") {
            analysis += "- Uses weak references\n"
        }
        if content.contains("unowned ") {
            analysis += "- Uses unowned references\n"
        }
        
        // Error Handling
        let errorPatterns = content.matches(of: try! Regex("(throws|throw|catch|try\\?|try!|do\\s*\\{)"))
        if !errorPatterns.isEmpty {
            analysis += "\nError Handling:\n"
            if content.contains("throws") {
                analysis += "- Uses throwing functions\n"
            }
            if content.contains("try?") {
                analysis += "- Uses optional try\n"
            }
            if content.contains("try!") {
                analysis += "- Warning: Uses force try\n"
            }
            if content.contains("catch") {
                analysis += "- Implements error catching\n"
            }
        }
        
        // Type System Usage
        analysis += "\nType System Features:\n"
        
        if content.contains("associatedtype") {
            analysis += "- Uses associated types\n"
        }
        if content.contains("some ") {
            analysis += "- Uses opaque return types\n"
        }
        if content.contains("any ") {
            analysis += "- Uses existential types\n"
        }
        if content.contains("where ") && (content.contains("extension") || content.contains("func")) {
            analysis += "- Uses generic constraints\n"
        }
        
        return analysis
    }
    
    private func analyzeSQL(_ content: String) async -> String {
        var analysis = "\nSQL Analysis:\n"
        
        // Detect SQL flavor and features
        if content.contains("ILIKE") || content.contains("RETURNING") || content.contains("JSONB") {
            analysis += "- PostgreSQL detected:\n"
            if content.contains("JSONB") {
                analysis += "  - Uses JSONB data type\n"
                if content.contains("->") || content.contains("->>") {
                    analysis += "  - Uses JSON operators\n"
                }
                if content.contains("@>") || content.contains("<@") {
                    analysis += "  - Uses containment operators\n"
                }
            }
            if content.contains("WITH RECURSIVE") {
                analysis += "  - Uses recursive CTEs\n"
            }
        } else if content.contains("LIMIT 1,1") || content.contains("JSON_EXTRACT") {
            analysis += "- MySQL detected:\n"
            if content.contains("JSON_EXTRACT") {
                analysis += "  - Uses JSON functions\n"
            }
            if content.contains("PARTITION BY") {
                analysis += "  - Uses partitioning\n"
            }
        } else if content.contains("TOP") || content.contains("CROSS APPLY") {
            analysis += "- SQL Server detected:\n"
            if content.contains("FOR XML") || content.contains("FOR JSON") {
                analysis += "  - Uses XML/JSON features\n"
            }
            if content.contains("TRY_CONVERT") {
                analysis += "  - Uses error handling functions\n"
            }
        }
        
        return analysis
    }
    
    private func analyzeMongoDBOperations(_ content: String) async -> String {
        var analysis = "\nMongoDB Analysis:\n"
        
        // CRUD Operations
        if content.contains(".find(") {
            analysis += "- Read Operations:\n"
            if content.contains(".aggregate(") {
                analysis += "  - Uses aggregation pipeline\n"
                if content.contains("$lookup") {
                    analysis += "  - Performs collection joins\n"
                }
                if content.contains("$group") {
                    analysis += "  - Uses grouping operations\n"
                }
            }
            if content.contains(".findOne(") {
                analysis += "  - Single document queries\n"
            }
        }
        
        if content.contains(".insert") {
            analysis += "- Write Operations:\n"
            if content.contains(".insertMany(") {
                analysis += "  - Bulk inserts\n"
            }
            if content.contains("ordered: false") {
                analysis += "  - Uses unordered bulk operations\n"
            }
        }
        
        // Indexing
        if content.contains(".createIndex(") {
            analysis += "\nIndex Operations:\n"
            if content.contains("unique:") {
                analysis += "- Creates unique indexes\n"
            }
            if content.contains("sparse:") {
                analysis += "- Uses sparse indexes\n"
            }
            if content.contains("text:") {
                analysis += "- Implements text search indexes\n"
            }
        }
        
        // Advanced Features
        if content.contains(".watch(") {
            analysis += "\nAdvanced Features:\n"
            analysis += "- Uses change streams\n"
        }
        if content.contains("$graphLookup") {
            analysis += "- Implements graph operations\n"
        }
        
        // Performance Considerations
        if content.contains(".explain(") {
            analysis += "\nPerformance Analysis:\n"
            analysis += "- Uses query explanation\n"
        }
        
        return analysis
    }
    
    private func analyzeDockerfile(_ content: String) async -> String {
        var analysis = "\nDockerfile Analysis:\n"
        let lines = content.components(separatedBy: .newlines)
        
        // Base Image Analysis
        if let baseImage = lines.first(where: { $0.hasPrefix("FROM") }) {
            analysis += "Base Image:\n"
            if baseImage.contains("alpine") {
                analysis += "- Uses Alpine Linux (minimal size)\n"
            } else if baseImage.contains("slim") {
                analysis += "- Uses slim variant\n"
            }
            if baseImage.contains(":latest") {
                analysis += "- Warning: Using 'latest' tag (consider using specific version)\n"
            }
        }
        
        // Build Optimization
        if lines.filter({ $0.hasPrefix("FROM") }).count > 1 {
            analysis += "\nBuild Optimization:\n"
            analysis += "- Uses multi-stage builds\n"
            if content.contains("COPY --from=") {
                analysis += "- Copies artifacts between stages\n"
            }
        }
        
        // Cache Optimization
        var cacheScore = 0
        analysis += "\nCache Optimization:\n"
        if content.contains("COPY package*.json") {
            analysis += "- Optimizes dependency caching\n"
            cacheScore += 1
        }
        if content.contains("RUN --mount=type=cache") {
            analysis += "- Uses BuildKit cache mounting\n"
            cacheScore += 2
        }
        
        // Security Analysis
        analysis += "\nSecurity Analysis:\n"
        if !content.contains("USER ") {
            analysis += "- Warning: No user specified (runs as root)\n"
        }
        if content.contains("chmod 777") {
            analysis += "- Warning: Overly permissive file permissions\n"
        }
        if content.contains("COPY --chown=") {
            analysis += "- Sets proper file ownership\n"
        }
        if !content.contains("HEALTHCHECK") {
            analysis += "- Warning: No health check defined\n"
        }
        
        // Best Practices
        analysis += "\nBest Practices:\n"
        if content.contains("HEALTHCHECK") {
            analysis += "- Implements health checks\n"
        }
        if content.contains("ONBUILD") {
            analysis += "- Uses ONBUILD triggers\n"
        }
        if content.contains("ARG") {
            analysis += "- Uses build arguments for configuration\n"
        }
        if content.contains("ENTRYPOINT") && content.contains("CMD") {
            analysis += "- Properly configures ENTRYPOINT with CMD\n"
        }
        
        // Size Optimization
        analysis += "\nSize Optimization:\n"
        if content.contains("rm -rf") && content.contains("/var/cache") {
            analysis += "- Cleans package cache\n"
        }
        if content.contains("--no-cache") {
            analysis += "- Uses no-cache flag for package managers\n"
        }
        if lines.contains(where: { $0.contains("&&") && $0.contains("\\") }) {
            analysis += "- Combines RUN commands to reduce layers\n"
        }
        
        // Runtime Configuration
        analysis += "\nRuntime Configuration:\n"
        if content.contains("ENV ") {
            analysis += "- Sets environment variables\n"
        }
        if content.contains("VOLUME") {
            analysis += "- Defines persistent storage\n"
        }
        if content.contains("EXPOSE") {
            analysis += "- Exposes ports\n"
        }
        
        return analysis
    }
    
    private func analyzeSvelte(_ content: String) async -> String {
        var analysis = "\nSvelte Analysis:\n"
        
        // Component Structure
        if content.contains("<script") {
            analysis += "- Contains script section\n"
            if content.contains("export let") {
                analysis += "  - Uses props\n"
            }
            if content.contains("$:") {
                analysis += "  - Uses reactive declarations\n"
            }
            if content.contains("onMount") {
                analysis += "  - Uses lifecycle methods\n"
            }
        }
        
        // Stores
        if content.contains("import { writable }") || content.contains("import { readable }") {
            analysis += "- Uses Svelte stores for state management\n"
        }
        
        // Transitions and Animations
        if content.contains("transition:") || content.contains("animate:") {
            analysis += "- Implements animations/transitions\n"
        }
        
        // Actions
        if content.contains("use:") {
            analysis += "- Uses Svelte actions\n"
        }
        
        // Event Handling
        if content.contains("on:") {
            analysis += "- Uses event handlers\n"
            if content.contains("preventDefault") {
                analysis += "  - Implements event modifiers\n"
            }
        }
        
        return analysis
    }
    
    private func analyzeComments(_ content: String) async -> String {
        var analysis = "\nComment Analysis:\n"
        
        // Extract comments
        var comments: [String] = []
        var docComments: [String] = []
        var inDocComment = false
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") || trimmed.hasPrefix("/**") {
                inDocComment = true
                let comment = trimmed.replacingOccurrences(of: "///", with: "")
                    .replacingOccurrences(of: "/**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                docComments.append(comment)
            } else if trimmed.hasPrefix("*/") {
                inDocComment = false
            } else if inDocComment {
                let comment = trimmed.replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty {
                    docComments.append(comment)
                }
            } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") {
                let comment = trimmed.replacingOccurrences(of: "//", with: "")
                    .replacingOccurrences(of: "/*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty {
                    comments.append(comment)
                }
            }
        }
        
        // Documentation Coverage Analysis
        if !docComments.isEmpty {
            analysis += "\nDocumentation Coverage:\n"
            let docText = docComments.joined(separator: " ")
            
            // Check for key documentation components
            let hasParameters = docText.contains("@param") || docText.contains("- Parameter")
            let hasReturns = docText.contains("@return") || docText.contains("- Returns")
            let hasExamples = docText.contains("Example") || docText.contains("Usage")
            
            var docScore = 0
            if hasParameters { docScore += 1 }
            if hasReturns { docScore += 1 }
            if hasExamples { docScore += 1 }
            
            analysis += "- Documentation Quality Score: \(docScore)/3\n"
            if !hasParameters { analysis += "  Warning: Missing parameter documentation\n" }
            if !hasReturns { analysis += "  Warning: Missing return value documentation\n" }
            if !hasExamples { analysis += "  Warning: Missing usage examples\n" }
        }
        
        // Technical Debt Analysis
        let technicalDebtIndicators = [
            "TODO": "planned enhancement",
            "FIXME": "known issue",
            "HACK": "implementation concern",
            "XXX": "critical concern",
            "OPTIMIZE": "performance concern",
            "WORKAROUND": "temporary solution"
        ]
        
        var debtAnalysis: [String: [(String, String)]] = [:]
        for comment in comments {
            for (indicator, type) in technicalDebtIndicators {
                if comment.contains(indicator) {
                    debtAnalysis[type, default: []].append((indicator, comment))
                }
            }
        }
        
        if !debtAnalysis.isEmpty {
            analysis += "\nTechnical Debt Analysis:\n"
            for (type, items) in debtAnalysis {
                analysis += "- \(type.capitalized):\n"
                for (indicator, comment) in items {
                    analysis += "  [\(indicator)] \(comment)\n"
                }
            }
        }
        
        return analysis
    }
    
    private func analyzeSemantics(_ content: String, tagger: NLTagger) async -> String {
        var analysis = "\nSemantic Analysis:\n"
        
        // Domain Language Analysis
        let domainTerms = await extractDomainTerms(from: content)
        if !domainTerms.isEmpty {
            analysis += "\nDomain-Specific Language:\n"
            for (category, terms) in domainTerms {
                analysis += "- \(category):\n"
                for term in terms {
                    analysis += "  - \(term)\n"
                }
            }
        }
        
        // Code Intent Analysis
        let intentAnalysis = await analyzeCodeIntent(content)
        if !intentAnalysis.isEmpty {
            analysis += "\nCode Intent Analysis:\n"
            for (intent, confidence) in intentAnalysis {
                analysis += "- \(intent): \(Int(confidence * 100))% confidence\n"
            }
        }
        
        return analysis
    }
    
    private func extractDomainTerms(from content: String) async -> [String: Set<String>] {
        var domainTerms: [String: Set<String>] = [:]
        
        // Define domain categories and their indicators
        let domainPatterns: [String: [String]] = [
            "Data Processing": ["process", "transform", "convert", "parse", "format"],
            "Authentication": ["auth", "login", "password", "credential", "token"],
            "Database Operations": ["query", "insert", "update", "delete", "select"],
            "Network Operations": ["request", "response", "http", "api", "endpoint"],
            "UI Components": ["view", "button", "label", "window", "screen"],
            "Error Handling": ["error", "exception", "catch", "throw", "handle"],
            "Configuration": ["config", "setting", "preference", "option", "setup"]
        ]
        
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        for (category, patterns) in domainPatterns {
            var terms = Set<String>()
            for word in words {
                if patterns.contains(where: { word.lowercased().contains($0) }) {
                    terms.insert(word)
                }
            }
            if !terms.isEmpty {
                domainTerms[category] = terms
            }
        }
        
        return domainTerms
    }
    
    private func analyzeCodeIntent(_ content: String) async -> [(String, Double)] {
        var intents: [(String, Double)] = []
        
        // Define intent patterns and their weights
        let intentPatterns: [(String, [(pattern: String, weight: Double)])] = [
            ("Data Validation", [("validate", 0.8), ("check", 0.6), ("verify", 0.7)]),
            ("Data Transformation", [("convert", 0.8), ("transform", 0.9), ("parse", 0.7)]),
            ("Security Implementation", [("encrypt", 0.9), ("decrypt", 0.9), ("hash", 0.8)]),
            ("Caching Logic", [("cache", 0.8), ("store", 0.6), ("retrieve", 0.6)]),
            ("Error Recovery", [("recover", 0.8), ("retry", 0.7), ("fallback", 0.8)]),
            ("Performance Optimization", [("optimize", 0.8), ("improve", 0.6), ("enhance", 0.6)])
        ]
        
        for (intent, patterns) in intentPatterns {
            var confidence = 0.0
            var matches = 0
            
            for (pattern, weight) in patterns {
                if content.lowercased().contains(pattern) {
                    confidence += weight
                    matches += 1
                }
            }
            
            if matches > 0 {
                confidence /= Double(patterns.count)
                if confidence > 0.3 { // Only include if confidence is significant
                    intents.append((intent, confidence))
                }
            }
        }
        
        return intents.sorted { $0.1 > $1.1 }
    }
    
    private func analyzeComplexity(_ content: String) async -> String {
        var analysis = "\nComplexity Analysis:\n"
        let lines = content.components(separatedBy: .newlines)
        
        // Cyclomatic complexity (rough estimate)
        let controlFlow = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.contains("if ") || 
                   trimmed.contains("for ") || 
                   trimmed.contains("while ") || 
                   trimmed.contains("switch ") ||
                   trimmed.contains("catch ") ||
                   trimmed.contains("? :")
        }.count
        
        if controlFlow > 0 {
            analysis += "- Control flow complexity: \(controlFlow)\n"
            if controlFlow > 10 {
                analysis += "  - Warning: High complexity, consider refactoring\n"
            }
        }
        
        // Nesting depth
        var maxNesting = 0
        var currentNesting = 0
        for line in lines {
            currentNesting += line.filter { $0 == "{" }.count
            currentNesting -= line.filter { $0 == "}" }.count
            maxNesting = max(maxNesting, currentNesting)
        }
        
        if maxNesting > 0 {
            analysis += "- Maximum nesting depth: \(maxNesting)\n"
            if maxNesting > 4 {
                analysis += "  - Warning: Deep nesting, consider flattening\n"
            }
        }
        
        // Function length
        var currentFunctionLines = 0
        var maxFunctionLines = 0
        var inFunction = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Track function boundaries
            if trimmed.contains("func ") {
                inFunction = true
                currentFunctionLines = 0
            } else if inFunction {
                if trimmed == "}" {
                    inFunction = false
                    maxFunctionLines = max(maxFunctionLines, currentFunctionLines)
                } else {
                    currentFunctionLines += 1
                }
            }
        }
        
        if maxFunctionLines > 0 {
            analysis += "- Longest function: \(maxFunctionLines) lines\n"
            if maxFunctionLines > 30 {
                analysis += "  - Warning: Long function, consider breaking it down\n"
            }
        }
        
        return analysis
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
                    let processedContent = file.includeComments ? content : stripComments(from: content)
                    output += "```\n\(processedContent)\n```\n\n"
                }
            }
        case .html:
            output += "<h2>File Contents</h2>\n"
            for file in selectedFiles where !file.isDirectory {
                output += "<h3>\(file.name)</h3>\n<pre>\n"
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = file.includeComments ? content : stripComments(from: content)
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
                    let processedContent = file.includeComments ? content : stripComments(from: content)
                    output += "\(processedContent)\n\n"
                }
            }
        case .json:
            output += "\"files\": ["
            for file in selectedFiles where !file.isDirectory {
                if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                    let processedContent = file.includeComments ? content : stripComments(from: content)
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
                    let processedContent = file.includeComments ? content : stripComments(from: content)
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
    
    private func isHidden(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        return filename.hasPrefix(".")
    }
    
    private func stripComments(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var inMultilineComment = false
        var processedLines: [String] = []
        
        for line in lines {
            var processedLine = line
            
            // Handle multi-line comments
            if inMultilineComment {
                if let endIndex = processedLine.range(of: "*/")?.upperBound {
                    processedLine = String(processedLine[endIndex...])
                    inMultilineComment = false
                } else {
                    continue
                }
            }
            
            // Handle single-line comments
            if let commentIndex = processedLine.range(of: "//")?.lowerBound {
                processedLine = String(processedLine[..<commentIndex])
            }
            
            // Handle start of multi-line comments
            if let startIndex = processedLine.range(of: "/*")?.lowerBound {
                if let endIndex = processedLine[startIndex...].range(of: "*/")?.upperBound {
                    let preComment = processedLine[..<startIndex]
                    let postComment = processedLine[endIndex...]
                    processedLine = String(preComment) + String(postComment)
                } else {
                    processedLine = String(processedLine[..<startIndex])
                    inMultilineComment = true
                }
            }
            
            processedLines.append(processedLine)
        }
        
        return processedLines.joined(separator: "\n")
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