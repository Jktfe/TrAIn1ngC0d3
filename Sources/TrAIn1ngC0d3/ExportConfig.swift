import Foundation

struct ExportConfig {
    var includeSummaries: Bool = true
    var includeComments: Bool = true
    var stripComments: Bool = false
    var includeImages: Bool = true
    var showHiddenFiles: Bool = false
    var outputFormat: OutputFormat = .markdown
    
    enum OutputFormat: String, CaseIterable {
        case markdown = "Markdown"
        case html = "HTML"
        case plainText = "Plain Text"
        
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .html: return "html"
            case .plainText: return "txt"
            }
        }
    }
    
    init(
        includeSummaries: Bool = true,
        includeComments: Bool = true,
        stripComments: Bool = false,
        includeImages: Bool = true,
        showHiddenFiles: Bool = false,
        outputFormat: OutputFormat = .markdown
    ) {
        self.includeSummaries = includeSummaries
        self.includeComments = includeComments
        self.stripComments = stripComments
        self.includeImages = includeImages
        self.showHiddenFiles = showHiddenFiles
        self.outputFormat = outputFormat
    }
}