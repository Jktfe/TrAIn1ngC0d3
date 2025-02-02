import Foundation
import Combine

struct FileItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let isDirectory: Bool
    let isExcluded: Bool
    var isSelected: Bool
    var children: [FileItem]?
    
    init(name: String, path: String, isDirectory: Bool, isExcluded: Bool, isSelected: Bool = false, children: [FileItem]? = nil) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isExcluded = isExcluded
        self.isSelected = isSelected
        self.children = children
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }
    
    func allSelectedFiles() -> [FileItem] {
        var selectedFiles = [FileItem]()
        if isSelected && !isDirectory {
            selectedFiles.append(self)
        }
        if let children = children {
            selectedFiles.append(contentsOf: children.flatMap { $0.allSelectedFiles() })
        }
        return selectedFiles
    }
}

class FileSystemModel: ObservableObject {
    @Published var fileItems: [FileItem] = []
    @Published var selectedFiles: Set<FileItem> = []
    @Published var selectedFilePreview: String = ""
    @Published var lastClickedFileContent: String = ""
    @Published var lastClickedFileName: String = ""
    @Published var rootPath: String?
    @Published var savedSummaries: [SavedSummary] = []
    private let excludedDirectories: Set<String> = ["node_modules", ".venv", "venv", ".git"]
    var config: ExportConfig
    private var currentURL: URL?
    
    struct SavedSummary: Identifiable, Codable {
        let id: UUID
        let fileName: String
        let content: String
        let timestamp: Date
        var isIncluded: Bool
        
        init(fileName: String, content: String) {
            self.id = UUID()
            self.fileName = fileName
            self.content = content
            self.timestamp = Date()
            self.isIncluded = true
        }
    }
    
    init(config: ExportConfig = ExportConfig()) {
        self.config = config
    }
    
    var hasSelections: Bool {
        func hasSelectedItems(_ items: [FileItem]) -> Bool {
            for item in items {
                if item.isSelected {
                    return true
                }
                if let children = item.children, hasSelectedItems(children) {
                    return true
                }
            }
            return false
        }
        return hasSelectedItems(fileItems)
    }
    
    func loadDirectory(at url: URL) {
        currentURL = url
        refreshFileList()
    }
    
    private func loadFileItems(at url: URL) -> [FileItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
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
            
            // Skip excluded directories
            if isDirectory && excludedDirectories.contains(name) {
                return nil
            }
            
            let children = isDirectory ? loadFileItems(at: url) : nil
            return FileItem(
                name: name,
                path: path,
                isDirectory: isDirectory,
                isExcluded: false,
                children: children
            )
        }
    }
    
    func refreshFileList() {
        guard let url = currentURL else { return }
        fileItems = loadFileItems(at: url)
        
        // Preserve selection state for existing items
        let selectedPaths = selectedFiles.map { $0.path }
        updateSelectionStates(items: &fileItems, selectedPaths: selectedPaths)
    }
    
    private func updateSelectionStates(items: inout [FileItem], selectedPaths: [String]) {
        for index in items.indices {
            items[index].isSelected = selectedPaths.contains(items[index].path)
            if var children = items[index].children {
                updateSelectionStates(items: &children, selectedPaths: selectedPaths)
                items[index].children = children
            }
        }
    }
    
    func updatePreview() {
        selectedFilePreview = selectedFiles.map { $0.name }.joined(separator: "\n")
    }
    
    func toggleSelection(for item: FileItem) {
        let isSelected = !item.isSelected
        
        // Update the selection state
        if isSelected {
            selectedFiles.insert(item)
        } else {
            selectedFiles.remove(item)
        }
        
        // Update the file tree
        var updatedItems = fileItems
        _ = updateSelection(items: &updatedItems, path: item.path, isSelected: isSelected)
        fileItems = updatedItems
        
        // Update preview
        updatePreview()
    }
    
    func updateSelection(items: inout [FileItem], path: String, isSelected: Bool) -> Bool {
        var found = false
        for index in items.indices {
            if items[index].path == path {
                items[index].isSelected = isSelected
                if let children = items[index].children {
                    var updatedChildren = children
                    for childIndex in updatedChildren.indices where !updatedChildren[childIndex].isExcluded {
                        updatedChildren[childIndex].isSelected = isSelected
                        if updatedChildren[childIndex].children != nil {
                            _ = updateSelection(items: &updatedChildren, path: updatedChildren[childIndex].path, isSelected: isSelected)
                        }
                    }
                    items[index].children = updatedChildren
                }
                found = true
                break
            } else if let children = items[index].children {
                var updatedChildren = children
                if updateSelection(items: &updatedChildren, path: path, isSelected: isSelected) {
                    items[index].children = updatedChildren
                    found = true
                    break
                }
            }
        }
        return found
    }
    
    func previewFileContent(for item: FileItem) {
        guard !item.isDirectory else {
            lastClickedFileContent = ""
            lastClickedFileName = ""
            return
        }
        
        do {
            let content = try String(contentsOfFile: item.path, encoding: .utf8)
            lastClickedFileContent = content
            lastClickedFileName = item.name
        } catch {
            lastClickedFileContent = "Error loading file: \(error.localizedDescription)"
            lastClickedFileName = item.name
        }
    }
    
    func saveSummary(_ content: String, for fileName: String) {
        let summary = SavedSummary(fileName: fileName, content: content)
        savedSummaries.append(summary)
        // Could persist to disk here if needed
    }
    
    func toggleSummary(_ summary: SavedSummary) {
        if let index = savedSummaries.firstIndex(where: { $0.id == summary.id }) {
            savedSummaries[index].isIncluded.toggle()
        }
    }
    
    func generateFileTree(for items: Set<FileItem>) -> String {
        func buildTree(_ item: FileItem, depth: Int = 0) -> String {
            let indent = String(repeating: "  ", count: depth)
            var result = "\(indent)- \(item.name)\n"
            
            if let children = item.children?.filter({ !$0.isExcluded }) {
                for child in children.sorted(by: { $0.name < $1.name }) {
                    result += buildTree(child, depth: depth + 1)
                }
            }
            return result
        }
        
        return items.sorted(by: { $0.name < $1.name })
            .map { buildTree($0) }
            .joined()
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
        
        return output
    }
    
    func getFolderSummary(for item: FileItem) -> String {
        var summary = ""
        
        if item.isDirectory, let children = item.children {
            let files = children.filter { !$0.isDirectory }
            let folders = children.filter { $0.isDirectory }
            
            // Group files by extension
            let groupedFiles = Dictionary(grouping: files) { file -> String in
                let ext = (file.name as NSString).pathExtension.lowercased()
                return ext.isEmpty ? "no extension" : ext
            }
            
            summary += "# Folder Summary: \(item.name)\n\n"
            
            // Basic stats
            summary += "## Overview\n"
            summary += "- Total items: \(children.count)\n"
            summary += "- Files: \(files.count)\n"
            summary += "- Folders: \(folders.count)\n\n"
            
            // File types
            summary += "## File Types\n"
            for (ext, files) in groupedFiles.sorted(by: { $0.key < $1.key }) {
                summary += "- .\(ext): \(files.count) files\n"
                for file in files.sorted(by: { $0.name < $1.name }) {
                    summary += "  - \(file.name)\n"
                }
            }
            summary += "\n"
            
            // Subfolders
            if !folders.isEmpty {
                summary += "## Subfolders\n"
                for folder in folders.sorted(by: { $0.name < $1.name }) {
                    summary += "- \(folder.name)\n"
                }
            }
        }
        
        return summary
    }
}