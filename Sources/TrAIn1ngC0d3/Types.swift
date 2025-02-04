import SwiftUI

enum OutputFormat: String, CaseIterable {
    case markdown
    case html
    case plainText
    case json
    case text
    
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .plainText: return "txt"
        case .json: return "json"
        case .text: return "txt"
        }
    }
}
