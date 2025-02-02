import Foundation

struct CommentParser {
    static func removeComments(from content: String, fileExtension: String) -> String {
        let patterns = commentPatterns(for: fileExtension)
        var cleanedContent = content
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
            cleanedContent = regex?.stringByReplacingMatches(
                in: cleanedContent,
                options: [],
                range: NSRange(location: 0, length: cleanedContent.utf16.count),
                withTemplate: ""
            ) ?? cleanedContent
        }
        return cleanedContent
    }
    
    private static func commentPatterns(for fileExtension: String) -> [String] {
        switch fileExtension.lowercased() {
        case "swift":
            return ["//.*", "/\\*[\\s\\S]*?\\*/"]
        case "py":
            return ["#.*", "\"\"\"[\\s\\S]*?\"\"\"", "\"\"\"[\\s\\S]*?\"\"\""]
        default:
            return []
        }
    }
}
