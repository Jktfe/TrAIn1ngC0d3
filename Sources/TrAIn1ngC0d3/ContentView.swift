import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @StateObject private var fileSystem = FileSystemModel()
    @State private var includeImages = true
    @State private var outputFormat: OutputFormat = .markdown
    @State private var showSummarySheet = false
    @State private var currentSummaryFileName = ""
    @State private var currentSummaryContent = ""
    @State private var isEditingSummary = false
    @State private var isGeneratingSummary = false
    @State private var selectedFile: FileItem = FileItem(name: "", path: "", isDirectory: false)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with logo and actions
            HStack {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    .padding(.trailing, 8)
                
                Button(action: selectRootFolder) {
                    Label("Select Root", systemImage: "folder.badge.plus")
                }
                .buttonStyle(Theme.BorderedButtonStyle())
                
                if let path = fileSystem.rootPath {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(Theme.textColor)
                        .padding(.horizontal, 8)
                }
                
                Spacer()
            }
            .padding()
            .background(Theme.backgroundColor.opacity(0.8))
            
            Divider()
            
            HSplitView {
                // Left panel: File browser
                VStack(alignment: .leading, spacing: 0) {
                    Text("Files and Folders")
                        .font(.headline)
                        .foregroundColor(Theme.primaryColor)
                        .padding()
                    
                    List(fileSystem.fileItems, children: \.children) { item in
                        FileItemRow(item: item, isSelected: fileSystem.selectedFiles.contains(item)) {
                            fileSystem.toggleSelection(for: item)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            fileSystem.previewFileContent(for: item)
                            selectedFile = item
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 250)
                .background(Theme.backgroundColor.opacity(0.5))
                
                // Middle panel: File preview and analysis
                VStack(spacing: 15) {
                    if !fileSystem.lastClickedFileName.isEmpty {
                        Button("Generate Summary") {
                            isGeneratingSummary = true
                            Task {
                                let summary = await fileSystem.generateSummary(for: URL(fileURLWithPath: fileSystem.lastClickedFileName), content: fileSystem.lastClickedFileContent)
                                currentSummaryContent = summary
                                currentSummaryFileName = fileSystem.lastClickedFileName
                                showSummarySheet = true
                                isGeneratingSummary = false
                            }
                        }
                        .buttonStyle(Theme.BorderedButtonStyle())
                        .disabled(isGeneratingSummary)
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("File Preview: \(fileSystem.lastClickedFileName)")
                                    .font(.headline)
                                    .foregroundColor(Theme.primaryColor)
                                
                                ScrollView {
                                    Text(fileSystem.lastClickedFileContent)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .frame(height: 200)
                            }
                        }
                        .groupBoxStyle(CustomGroupBoxStyle())
                        
                        HStack(spacing: 15) {
                            // Imports section
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Imports From")
                                        .font(.headline)
                                        .foregroundColor(Theme.primaryColor)
                                    
                                    if let imports = fileSystem.fileImports[fileSystem.lastClickedFileName], !imports.isEmpty {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(Array(imports), id: \.self) { importedFile in
                                                    Text(importedFile)
                                                        .foregroundColor(Theme.textColor)
                                                }
                                            }
                                        }
                                    } else {
                                        Text("No imports found")
                                            .foregroundColor(Theme.textColor.opacity(0.6))
                                    }
                                }
                            }
                            .groupBoxStyle(CustomGroupBoxStyle())
                            
                            // Exports section
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Exports To")
                                        .font(.headline)
                                        .foregroundColor(Theme.primaryColor)
                                    
                                    if let exports = fileSystem.fileExports[fileSystem.lastClickedFileName], !exports.isEmpty {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(Array(exports), id: \.self) { exportedFile in
                                                    Text(URL(fileURLWithPath: exportedFile).lastPathComponent)
                                                        .foregroundColor(Theme.textColor)
                                                }
                                            }
                                        }
                                    } else {
                                        Text("No exports found")
                                            .foregroundColor(Theme.textColor.opacity(0.6))
                                    }
                                }
                            }
                            .groupBoxStyle(CustomGroupBoxStyle())
                        }
                        .frame(height: 150)
                    } else {
                        ContentUnavailableView {
                            Label("No File Selected", systemImage: "doc")
                        } description: {
                            Text("Select a file to view its contents and analysis")
                        }
                    }
                }
                
                // Right panel: Options and Summaries
                VStack(spacing: 15) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show Hidden Files", isOn: $fileSystem.config.showHiddenFiles)
                                .tint(Theme.primaryColor)
                            
                            Toggle(isOn: $includeImages) {
                                Label("Include Images", systemImage: "photo")
                                    .foregroundColor(Theme.textColor)
                            }
                            .tint(Theme.primaryColor)
                            
                            if !fileSystem.selectedFiles.isEmpty {
                                Divider()
                                Text("Selected Files")
                                    .font(.headline)
                                    .foregroundColor(Theme.textColor)
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(fileSystem.selectedFiles)) { file in
                                            if !file.isDirectory {
                                                HStack {
                                                    Text(file.name)
                                                        .foregroundColor(Theme.textColor)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Toggle("Comments", isOn: Binding(
                                                        get: { file.includeComments },
                                                        set: { newValue in
                                                            if let index = fileSystem.fileItems.firstIndex(where: { $0.id == file.id }) {
                                                                fileSystem.fileItems[index].includeComments = newValue
                                                                // Refresh content if this is the currently viewed file
                                                                if fileSystem.lastClickedFileName == file.path {
                                                                    fileSystem.previewFileContent(for: fileSystem.fileItems[index])
                                                                }
                                                            }
                                                        }
                                                    ))
                                                    .labelsHidden()
                                                    .tint(Theme.primaryColor)
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 150)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .groupBoxStyle(CustomGroupBoxStyle())
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summaries")
                                .font(.headline)
                                .foregroundColor(Theme.primaryColor)
                            
                            if fileSystem.savedSummaries.isEmpty {
                                Text("No summaries generated")
                                    .foregroundColor(Theme.textColor.opacity(0.6))
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(fileSystem.savedSummaries) { summary in
                                            HStack {
                                                Image(systemName: summary.isIncluded ? "checkmark.square.fill" : "square")
                                                    .foregroundColor(summary.isIncluded ? Theme.primaryColor : Theme.textColor.opacity(0.3))
                                                    .onTapGesture {
                                                        fileSystem.toggleSummary(summary)
                                                    }
                                                Text(summary.fileName)
                                                    .lineLimit(1)
                                                    .foregroundColor(Theme.textColor)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 100)
                            }
                        }
                    }
                    .groupBoxStyle(CustomGroupBoxStyle())
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Export Format")
                                .font(.headline)
                                .foregroundColor(Theme.primaryColor)
                            
                            Picker("", selection: $outputFormat) {
                                ForEach(OutputFormat.allCases, id: \.self) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 5)
                    }
                    .groupBoxStyle(CustomGroupBoxStyle())
                    
                    Button("Generate Export") {
                        exportContent(as: outputFormat)
                    }
                    .buttonStyle(Theme.BorderedButtonStyle())
                    .disabled(fileSystem.selectedFiles.isEmpty && fileSystem.savedSummaries.isEmpty)
                }
                .frame(width: 250)
                .padding()
                .background(Theme.backgroundColor.opacity(0.5))
            }
        }
        .sheet(isPresented: $showSummarySheet) {
            SummaryEditView(
                summary: $currentSummaryContent,
                onSave: {
                    fileSystem.saveSummary(currentSummaryContent, for: currentSummaryFileName)
                    showSummarySheet = false
                },
                onCancel: {
                    showSummarySheet = false
                },
                onRetry: {
                    isGeneratingSummary = true
                    Task {
                        let summary = await fileSystem.generateSummary(for: URL(fileURLWithPath: fileSystem.lastClickedFileName), content: fileSystem.lastClickedFileContent)
                        currentSummaryContent = summary
                        isGeneratingSummary = false
                    }
                }
            )
            .frame(width: 800, height: 600)
        }
    }
    
    private func selectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                fileSystem.loadDirectory(at: url)
            }
        }
    }
    
    private func exportContent(as format: OutputFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "export-\(ISO8601DateFormatter().string(from: Date()))"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                let content = fileSystem.generateExport(format: format)
                try? content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            }
        }
    }
}

struct ContentUnavailableView<Label: View>: View {
    let label: () -> Label
    let description: () -> Text
    
    var body: some View {
        VStack(spacing: 10) {
            label()
                .font(.system(.headline))
            description()
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FileItemRow: View {
    let item: FileItem
    let isSelected: Bool
    let toggleSelection: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                .foregroundColor(Theme.primaryColor.opacity(0.8))
            Text(item.name)
                .foregroundColor(Theme.textColor)
            
            if !item.isExcluded {
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in toggleSelection() }
                ))
            }
        }
        .contentShape(Rectangle())
    }
}

struct CustomGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.headline)
                .foregroundColor(Theme.primaryColor)
            
            configuration.content
                .padding(.top, 5)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}