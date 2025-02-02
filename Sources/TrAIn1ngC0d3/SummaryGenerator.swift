import Foundation
import NaturalLanguage

class SummaryGenerator {
    enum SummaryError: Error {
        case noFilesSelected
        case fileReadError(String)
        case summaryGenerationFailed(String)
    }
    
    public struct Summary {
        let content: String      // The generated summary text
        let analysis: String     // Technical analysis of the file (for preview)
        let fileName: String     // Name of the file being summarized
    }
    
    static func generateSummary(for files: [FileItem], additionalComments: String = "") throws -> Summary {
        guard !files.isEmpty else {
            throw SummaryError.noFilesSelected
        }
        
        // For now, we'll focus on the first selected file
        let file = files[0]
        guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
            throw SummaryError.fileReadError(file.name)
        }
        
        // Generate the technical analysis (this will be shown in the preview)
        var analysis = ""
        let fileExtension = (file.name as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "js", "jsx", "ts", "tsx":
            analysis = try analyzeJavaScript(content)
        case "py":
            analysis = try analyzePython(content)
        case "swift":
            analysis = try analyzeSwift(content)
        case "md", "markdown":
            analysis = try analyzeMarkdown(content)
        default:
            analysis = try analyzeGeneric(content)
        }
        
        // Generate the actual summary using the template
        let summary = try generateAISummary(
            fileName: file.name,
            content: content,
            analysis: analysis,
            additionalComments: additionalComments
        )
        
        return Summary(
            content: summary,
            analysis: analysis,
            fileName: file.name
        )
    }
    
    private static func generateAISummary(fileName: String, content: String, analysis: String, additionalComments: String = "") throws -> String {
        // This is where we'd ideally use an AI model to generate the summary
        // For now, we'll create a structured summary based on the analysis
        
        var summary = """
        FILENAME / FOLDER: \(fileName)
        
        Quick Summary:
        \(determineQuickSummary(fileName: fileName, content: content))
        
        Purpose:
        \(determinePurpose(fileName: fileName, content: content))
        
        Key Components:
        \(extractKeyComponents(from: analysis))
        
        Dependencies:
        \(analyzeDependencies(content: content))
        
        Technical Details:
        \(extractTechnicalDetails(from: analysis))
        
        Architecture Patterns:
        \(identifyArchitecturePatterns(content: content))
        
        Strengths:
        \(determineStrengths(from: analysis))
        
        Areas for Improvement:
        \(determineWeaknesses(from: analysis))
        
        Security Considerations:
        \(analyzeSecurityConsiderations(content: content))
        
        Performance Impact:
        \(analyzePerformance(content: content))
        
        Testing Status:
        \(analyzeTestingStatus(content: content))
        
        Notable Features:
        \(extractNotableFeatures(from: analysis))
        
        Documentation Status:
        \(analyzeDocumentation(content: content))
        
        Additional Notes:
        \(generateAdditionalNotes(fileName: fileName, content: content))
        """
        
        // If additional comments were provided, use them to enhance the summary
        if !additionalComments.isEmpty {
            summary += "\n\nUser Comments:\n\(additionalComments)"
        }
        
        return summary
    }
    
    private static func determineQuickSummary(fileName: String, content: String) -> String {
        let lines = content.components(separatedBy: .newlines).count
        let size = ByteCountFormatter.string(fromByteCount: Int64(content.count), countStyle: .file)
        return "A \(size) file containing \(lines) lines of code."
    }
    
    private static func analyzeDependencies(content: String) -> String {
        var dependencies: [String] = []
        
        // Look for common dependency patterns
        if content.contains("import ") {
            dependencies.append("- Has external imports")
        }
        if content.contains("@dependency") || content.contains("@Dependency") {
            dependencies.append("- Uses dependency injection")
        }
        if content.contains("require(") {
            dependencies.append("- Uses Node.js require system")
        }
        
        return dependencies.isEmpty ? "No explicit dependencies found." : dependencies.joined(separator: "\n")
    }
    
    private static func extractTechnicalDetails(from analysis: String) -> String {
        // Extract more detailed technical information
        let details = analysis.components(separatedBy: .newlines)
            .filter { $0.contains("•") || $0.contains("Found") || $0.contains("Uses") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        return details.isEmpty ? "No specific technical details found." : details.joined(separator: "\n")
    }
    
    private static func identifyArchitecturePatterns(content: String) -> String {
        var patterns: [String] = []
        
        // Look for common architecture patterns
        if content.contains("MVVM") || content.contains("ViewModel") {
            patterns.append("- MVVM Architecture Pattern")
        }
        if content.contains("MVC") || content.contains("Controller") {
            patterns.append("- MVC Architecture Pattern")
        }
        if content.contains("Redux") || content.contains("Store") {
            patterns.append("- Redux/Store Pattern")
        }
        if content.contains("Observable") || content.contains("Subject") {
            patterns.append("- Observer Pattern")
        }
        if content.contains("Factory") {
            patterns.append("- Factory Pattern")
        }
        if content.contains("Singleton") {
            patterns.append("- Singleton Pattern")
        }
        
        return patterns.isEmpty ? "No specific architecture patterns identified." : patterns.joined(separator: "\n")
    }
    
    private static func analyzeSecurityConsiderations(content: String) -> String {
        var considerations: [String] = []
        
        // Look for security-related patterns
        if content.contains("password") || content.contains("secret") {
            considerations.append("⚠️ Contains sensitive data handling")
        }
        if content.contains("encrypt") || content.contains("decrypt") {
            considerations.append("✓ Uses encryption")
        }
        if content.contains("sanitize") || content.contains("escape") {
            considerations.append("✓ Implements input sanitization")
        }
        if content.contains("auth") || content.contains("token") {
            considerations.append("⚠️ Contains authentication logic")
        }
        
        return considerations.isEmpty ? "No immediate security concerns identified." : considerations.joined(separator: "\n")
    }
    
    private static func analyzePerformance(content: String) -> String {
        var performance: [String] = []
        
        // Look for performance-related patterns
        if content.contains("async") || content.contains("await") {
            performance.append("+ Uses async/await for better performance")
        }
        if content.contains("cache") {
            performance.append("+ Implements caching")
        }
        if content.contains("O(n)") || content.contains("complexity") {
            performance.append("! Contains complexity considerations")
        }
        if content.contains("optimize") || content.contains("performance") {
            performance.append("+ Contains performance optimizations")
        }
        
        return performance.isEmpty ? "No specific performance patterns identified." : performance.joined(separator: "\n")
    }
    
    private static func analyzeTestingStatus(content: String) -> String {
        var testing: [String] = []
        
        // Look for test-related patterns
        if content.contains("test") || content.contains("spec") {
            testing.append("✓ Contains test code")
        }
        if content.contains("mock") || content.contains("stub") {
            testing.append("✓ Uses test doubles")
        }
        if content.contains("describe") || content.contains("it(") {
            testing.append("✓ Uses BDD testing style")
        }
        if content.contains("assert") {
            testing.append("✓ Contains assertions")
        }
        
        return testing.isEmpty ? "No test coverage found." : testing.joined(separator: "\n")
    }
    
    private static func analyzeDocumentation(content: String) -> String {
        var docs: [String] = []
        
        // Count comments and documentation
        let commentLines = content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .count
        
        let docCommentLines = content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("///") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("/**") }
            .count
        
        if commentLines > 0 {
            docs.append("- Contains \(commentLines) lines of inline comments")
        }
        if docCommentLines > 0 {
            docs.append("- Contains \(docCommentLines) lines of documentation comments")
        }
        if content.contains("TODO:") || content.contains("FIXME:") {
            docs.append("! Contains TODO/FIXME markers")
        }
        
        return docs.isEmpty ? "No documentation found." : docs.joined(separator: "\n")
    }
    
    private static func determinePurpose(fileName: String, content: String) -> String {
        // This would use AI to determine the purpose
        // For now, we'll make a basic determination
        if fileName.lowercased().contains("test") {
            return "This is a test file that verifies functionality of the codebase."
        } else if fileName.lowercased().contains("model") {
            return "This is a data model file that defines the structure of the application's data."
        } else {
            return "This file appears to be a component of the application's core functionality."
        }
    }
    
    private static func extractKeyComponents(from analysis: String) -> String {
        // Extract key components from the analysis
        // This would be more sophisticated with AI
        return analysis.components(separatedBy: .newlines)
            .filter { $0.contains("•") }
            .joined(separator: "\n")
    }
    
    private static func determineStrengths(from analysis: String) -> String {
        // This would use AI to determine strengths
        // For now, return a placeholder
        return "- Well-structured code organization\n- Clear naming conventions"
    }
    
    private static func determineWeaknesses(from analysis: String) -> String {
        // This would use AI to determine areas for improvement
        // For now, return a placeholder
        return "- Could benefit from additional documentation\n- Consider adding error handling"
    }
    
    private static func extractNotableFeatures(from analysis: String) -> String {
        // This would use AI to identify notable features
        // For now, extract anything that seems important from the analysis
        return analysis.components(separatedBy: .newlines)
            .filter { $0.contains("Found") || $0.contains("Detected") }
            .joined(separator: "\n")
    }
    
    private static func generateAdditionalNotes(fileName: String, content: String) -> String {
        // This would use AI to generate additional insights
        // For now, return basic file statistics
        return "File size: \(ByteCountFormatter.string(fromByteCount: Int64(content.count), countStyle: .file))"
    }
    
    // Keep the existing analysis functions but rename them
    private static func analyzeJavaScript(_ content: String) throws -> String {
        var analysis = ""
        // Find imports/requires
        let importRegex = try NSRegularExpression(pattern: "(import\\s+\\{[^}]+\\}\\s+from|import\\s+[^;]+from|require\\(['\"][^'\"]+['\"]\\))\\s*['\"]([^'\"]+)['\"]", options: [])
        let importMatches = importRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let imports = Set(importMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 2), in: content) else { return nil }
            return String(content[range])
        })
        
        if !imports.isEmpty {
            analysis += "  • Imports: \(imports.joined(separator: ", "))\n"
        }
        
        // Find classes
        let classRegex = try NSRegularExpression(pattern: "class\\s+(\\w+)(?:\\s+extends\\s+(\\w+))?\\s*\\{", options: [])
        let classMatches = classRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let classes = classMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            var name = String(content[range])
            if let extendRange = Range(match.range(at: 2), in: content) {
                name += " extends " + String(content[extendRange])
            }
            return name
        }
        
        if !classes.isEmpty {
            analysis += "  • Classes: \(classes.joined(separator: ", "))\n"
        }
        
        // Find async functions
        let asyncFuncRegex = try NSRegularExpression(pattern: "async\\s+(?:function\\s+)?(\\w+)\\s*\\(", options: [])
        let asyncFuncMatches = asyncFuncRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let asyncFuncs = asyncFuncMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !asyncFuncs.isEmpty {
            analysis += "  • Async Functions: \(asyncFuncs.joined(separator: ", "))\n"
        }
        
        // Find event listeners
        let eventRegex = try NSRegularExpression(pattern: "addEventListener\\(['\"]([^'\"]+)['\"]", options: [])
        let eventMatches = eventRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let events = Set(eventMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        })
        
        if !events.isEmpty {
            analysis += "  • Event Listeners: \(events.joined(separator: ", "))\n"
        }
        
        // Find promises
        if content.contains("new Promise") {
            analysis += "  • Uses Promises: Yes\n"
        }
        
        // Find exports
        let exportRegex = try NSRegularExpression(pattern: "(?:export\\s+(?:default\\s+)?(?:class|function|const|let|var)\\s+(\\w+)|module\\.exports\\s*=|exports\\.([\\w]+)\\s*=)", options: [])
        let exportMatches = exportRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let exports = exportMatches.compactMap { match -> String? in
            if let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
            if let range = Range(match.range(at: 2), in: content) {
                return String(content[range])
            }
            return nil
        }
        
        if !exports.isEmpty {
            analysis += "  • Exports: \(exports.joined(separator: ", "))\n"
        }
        
        return analysis
    }
    
    private static func analyzePython(_ content: String) throws -> String {
        var analysis = ""
        // Find classes
        let classRegex = try NSRegularExpression(pattern: "class\\s+(\\w+)(?:\\([^)]*\\))?:", options: [])
        let classMatches = classRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let classNames = classMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !classNames.isEmpty {
            analysis += "  • Classes: \(classNames.joined(separator: ", "))\n"
        }
        
        // Find functions
        let funcRegex = try NSRegularExpression(pattern: "def\\s+(\\w+)\\s*\\(", options: [])
        let funcMatches = funcRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let funcNames = funcMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !funcNames.isEmpty {
            analysis += "  • Functions: \(funcNames.joined(separator: ", "))\n"
        }
        
        // Find decorators
        let decoratorRegex = try NSRegularExpression(pattern: "@(\\w+)", options: [])
        let decoratorMatches = decoratorRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let decorators = Set(decoratorMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        })
        
        if !decorators.isEmpty {
            analysis += "  • Decorators: \(decorators.joined(separator: ", "))\n"
        }
        
        return analysis
    }
    
    private static func analyzeSwift(_ content: String) throws -> String {
        var analysis = ""
        // Find classes
        let classRegex = try NSRegularExpression(pattern: "class\\s+(\\w+)", options: [])
        let classMatches = classRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let classNames = classMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !classNames.isEmpty {
            analysis += "  • Classes: \(classNames.joined(separator: ", "))\n"
        }
        
        // Find structs
        let structRegex = try NSRegularExpression(pattern: "struct\\s+(\\w+)", options: [])
        let structMatches = structRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let structNames = structMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !structNames.isEmpty {
            analysis += "  • Structs: \(structNames.joined(separator: ", "))\n"
        }
        
        // Find functions
        let funcRegex = try NSRegularExpression(pattern: "func\\s+(\\w+)", options: [])
        let funcMatches = funcRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let funcNames = funcMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
        
        if !funcNames.isEmpty {
            analysis += "  • Functions: \(funcNames.joined(separator: ", "))\n"
        }
        
        return analysis
    }
    
    private static func analyzeMarkdown(_ content: String) throws -> String {
        var analysis = ""
        // Find headers with content
        let headerRegex = try NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: [.anchorsMatchLines])
        let headerMatches = headerRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        var headers: [Int: [(level: Int, title: String)]] = [:]
        headerMatches.forEach { match in
            if let levelRange = Range(match.range(at: 1), in: content),
               let titleRange = Range(match.range(at: 2), in: content) {
                let level = content[levelRange].count
                let title = String(content[titleRange])
                headers[level, default: []].append((level: level, title: title))
            }
        }
        
        if !headers.isEmpty {
            // Show counts
            let headerSummary = headers.sorted { $0.key < $1.key }
                .map { "H\($0.key): \($0.value.count)" }
                .joined(separator: ", ")
            analysis += "  • Headers: \(headerSummary)\n"
            
            // Show top-level structure
            if let h1s = headers[1] {
                analysis += "  • Document Structure:\n"
                for h1 in h1s {
                    analysis += "    ◦ \(h1.title)\n"
                }
            }
        }
        
        // Find links with titles
        let linkRegex = try NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
        let linkMatches = linkRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        var links: [(title: String, url: String)] = []
        linkMatches.forEach { match in
            if let titleRange = Range(match.range(at: 1), in: content),
               let urlRange = Range(match.range(at: 2), in: content) {
                links.append((
                    title: String(content[titleRange]),
                    url: String(content[urlRange])
                ))
            }
        }
        
        if !links.isEmpty {
            analysis += "  • Links (\(links.count)):\n"
            // Show first few links
            for link in links.prefix(3) {
                analysis += "    ◦ \(link.title) -> \(link.url)\n"
            }
            if links.count > 3 {
                analysis += "    ◦ ... and \(links.count - 3) more\n"
            }
        }
        
        // Find tables
        let tableRegex = try NSRegularExpression(pattern: "\\|[^\\n]+\\|\\s*\\n\\|[-:\\s|]+\\|", options: [])
        let tableMatches = tableRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        if !tableMatches.isEmpty {
            analysis += "  • Tables: \(tableMatches.count)\n"
        }
        
        // Find task lists
        let taskRegex = try NSRegularExpression(pattern: "^\\s*- \\[([ x])\\]", options: [.anchorsMatchLines])
        let taskMatches = taskRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        if !taskMatches.isEmpty {
            var completed = 0
            taskMatches.forEach { match in
                if let checkRange = Range(match.range(at: 1), in: content),
                   content[checkRange] == "x" {
                    completed += 1
                }
            }
            analysis += "  • Tasks: \(completed)/\(taskMatches.count) completed\n"
        }
        
        // Find code blocks with language and preview
        let codeBlockRegex = try NSRegularExpression(pattern: "```([a-zA-Z0-9]*)\\s*\\n([^`]+)```", options: [])
        let codeBlockMatches = codeBlockRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        var codeBlocks: [(lang: String, preview: String)] = []
        codeBlockMatches.forEach { match in
            if let langRange = Range(match.range(at: 1), in: content),
               let codeRange = Range(match.range(at: 2), in: content) {
                let lang = String(content[langRange])
                let code = String(content[codeRange])
                let preview = String(code.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                codeBlocks.append((
                    lang: lang.isEmpty ? "plain" : lang,
                    preview: preview
                ))
            }
        }
        
        if !codeBlocks.isEmpty {
            analysis += "  • Code Blocks (\(codeBlocks.count)):\n"
            let languages = Set(codeBlocks.map { $0.lang })
            analysis += "    ◦ Languages: \(languages.joined(separator: ", "))\n"
            // Show preview of first code block
            if let first = codeBlocks.first {
                analysis += "    ◦ First Block (\(first.lang)): \(first.preview)...\n"
            }
        }
        
        return analysis
    }
    
    private static func analyzeGeneric(_ content: String) throws -> String {
        var analysis = ""
        let tagger = NLTagger(tagSchemes: [.lemma, .nameType])
        tagger.string = content
        
        // Get important terms
        var terms: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: content.startIndex..<content.endIndex, 
                           unit: .word,
                           scheme: .lemma,
                           options: options) { tag, range in
            if let lemma = tag?.rawValue {
                let word = lemma.lowercased()
                if word.count > 3 && !commonWords.contains(word) {
                    terms[word, default: 0] += 1
                }
            }
            return true
        }
        
        // Get top terms
        let topTerms = terms.sorted { $0.value > $1.value }.prefix(5)
        if !topTerms.isEmpty {
            analysis += "  • Common Terms: \(topTerms.map { "\($0.key)" }.joined(separator: ", "))\n"
        }
        
        return analysis
    }
    
    // Common words to filter out
    private static let commonWords: Set<String> = ["this", "that", "these", "those", "have", "from", "will", 
                                                 "what", "when", "where", "which", "with", "would"]
}
