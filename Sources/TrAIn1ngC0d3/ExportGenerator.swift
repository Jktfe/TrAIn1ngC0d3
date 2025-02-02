import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
class ExportGenerator {
    private let model: FileSystemModel
    private let outputFormat: OutputFormat
    
    init(model: FileSystemModel, outputFormat: OutputFormat) {
        self.model = model
        self.outputFormat = outputFormat
    }
    
    func generateExport() -> URL? {
        let selectedFiles = model.selectedFiles.filter { !$0.isDirectory }
        let content = processFiles(Array(selectedFiles))
        return createOutputFile(content: content)
    }
    
    private func processFiles(_ files: [FileItem]) -> String {
        var content = ""
        
        // Add header
        let timestamp = ISO8601DateFormatter().string(from: Date())
        content += "# File Analysis - \(timestamp)\n\n"
        
        // Add file list
        content += "## Files Analyzed\n\n"
        for file in files {
            content += "- \(file.name)\n"
        }
        content += "\n"
        
        // Add summaries
        content += "## Summaries\n\n"
        for summary in model.savedSummaries where summary.isIncluded {
            content += "### \(summary.fileName)\n\n"
            content += summary.content
            content += "\n\n"
        }
        
        return content
    }
    
    private func createOutputFile(content: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileName = "export-\(timestamp).\(outputFormat.fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            #if os(macOS)
            NSWorkspace.shared.open(tempDir) // Reveal in Finder
            if let sound = NSSound(named: NSSound.Name("Basso")) {
                sound.play()
            }
            #endif
            return fileURL
        } catch {
            print("Export error: \(error.localizedDescription)")
            #if os(macOS)
            if let sound = NSSound(named: NSSound.Name("Basso")) {
                sound.play()
            }
            #endif
            return nil
        }
    }
}