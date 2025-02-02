import Foundation
import NaturalLanguage

class ExportGenerator: ObservableObject {
    @Published var progress: Double = 0
    private let config: ExportConfig
    private let model: FileSystemModel
    
    init(config: ExportConfig, model: FileSystemModel) {
        self.config = config
        self.model = model
    }
    
    func generateExport() -> URL? {
        let selectedFiles = model.fileItems.filter { $0.isSelected && !$0.isDirectory }
        let content = processFiles(selectedFiles)
        return createOutputFile(content: content)
    }
    
    private func processFiles(_ files: [FileItem]) -> String {
        var output = ""
        switch config.outputFormat {
        case .markdown: output += "# Project Export\n\n"
        case .html: output += "<!DOCTYPE html>\n<html>\n<body>\n<h1>Project Export</h1>\n"
        default: break
        }
        
        for file in files {
            if config.includeImages && isImageFile(file.path) {
                output += formatImageSection(file: file)
                continue
            }
            
            guard let content = try? String(contentsOfFile: file.path) else { continue }
            let processedContent = config.stripComments ? 
                CommentParser.removeComments(from: content, fileExtension: URL(fileURLWithPath: file.path).pathExtension) : 
                content
            
            output += formatSection(title: file.name, content: processedContent)
        }
        
        if config.outputFormat == .html {
            output += "</body>\n</html>"
        }
        return output
    }
    
    private func formatSection(title: String, content: String) -> String {
        switch config.outputFormat {
        case .markdown:
            return "## \(title)\n```\(fileExtensionToLanguage(title))\n\(content)\n```\n\n"
        case .html:
            return "<h2>\(title)</h2>\n<pre><code>\(content)</code></pre>\n"
        default:
            return "=== \(title) ===\n\(content)\n\n"
        }
    }
    
    private func fileExtensionToLanguage(_ path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "html": return "html"
        case "css": return "css"
        default: return ""
        }
    }
    
    private func isImageFile(_ path: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif"]
        return imageExtensions.contains(URL(fileURLWithPath: path).pathExtension)
    }
    
    private func formatImageSection(file: FileItem) -> String {
        switch config.outputFormat {
        case .markdown: return "![\(file.name)](\(file.path))\n\n"
        case .html: return "<img src=\"\(file.path)\" alt=\"\(file.name)\">\n"
        default: return "Image: \(file.path)\n"
        }
    }
    
// Change variable name from 'extension' to 'fileExtension'
private func createOutputFile(content: String) -> URL? {
    let tempDir = FileManager.default.temporaryDirectory
    let fileExtension = config.outputFormat == .html ? "html" : "md"
    let outputFile = tempDir.appendingPathComponent("Export-\(Date().timeIntervalSince1970).\(fileExtension)")
    
    do {
        try content.write(to: outputFile, atomically: true, encoding: .utf8)
        return outputFile
    } catch {
        return nil
    }
}
}