import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var fileSystem = FileSystemModel()
    @State private var showHiddenFiles = false {
        didSet {
            fileSystem.config.showHiddenFiles = showHiddenFiles
            fileSystem.refreshFileList()
        }
    }
    @State private var includeImages = true
    @State private var outputFormat: ExportConfig.OutputFormat = ExportConfig.OutputFormat.markdown
    @State private var generatedSummary: SummaryGenerator.Summary?
    @State private var isEditingSummary = false
    @State private var editedSummary: String = ""
    @State private var additionalComments: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    enum OutputFormat: String, CaseIterable {
        case markdown = "Markdown"
        case html = "HTML"
        case plainText = "Plain Text"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Root folder selection
            HStack {
                Button(action: selectRootFolder) {
                    Label("Select Root", systemImage: "folder.badge.plus")
                }
                if let path = fileSystem.rootPath {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding()
            .frame(height: 50)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Left panel: File browser
                VStack(alignment: .leading, spacing: 0) {
                    Text("Files and Folders:")
                        .font(.headline)
                        .padding()
                        .frame(height: 50)
                    
                    FileTreeView(fileSystem: fileSystem, showHiddenFiles: showHiddenFiles)
                        .frame(minWidth: 250)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                
                // Center panel: Actions and Preview
                VStack(spacing: 0) {
                    // Action buttons
                    VStack(spacing: 8) {
                        Button(action: generateSummary) {
                            Text("Generate Summary")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(fileSystem.selectedFiles.isEmpty)
                        
                        if fileSystem.selectedFiles.isEmpty {
                            Text("Select one or more files to generate a summary")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .padding()
                    .frame(height: 80)
                    
                    Divider()
                    
                    // Preview area with consistent height
                    ScrollView {
                        if let preview = fileSystem.lastClickedFileName.isEmpty ? nil : fileSystem.lastClickedFileContent {
                            GroupBox(label: Text("File Preview: \(fileSystem.lastClickedFileName)")) {
                                Text(preview)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding()
                        } else {
                            ContentUnavailableView {
                                Label("No Preview", systemImage: "doc.text")
                            } description: {
                                Text("Click a file to preview its contents")
                            }
                            .frame(maxHeight: CGFloat.infinity)
                        }
                    }
                }
                .frame(minWidth: 400)
                .background(Color(nsColor: .windowBackgroundColor))
                
                // Right panel: Options and Summaries
                VStack(spacing: 15) {
                    // Content Options
                    GroupBox(label: Text("Content Options")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $showHiddenFiles) {
                                HStack {
                                    Text("Show Hidden Files")
                                    Image(systemName: "eye")
                                        .foregroundColor(showHiddenFiles ? .accentColor : .secondary)
                                }
                            }
                            .onChange(of: showHiddenFiles) { oldValue, newValue in
                                fileSystem.config.showHiddenFiles = newValue
                                fileSystem.refreshFileList()
                            }
                            
                            Toggle(isOn: $includeImages) {
                                HStack {
                                    Text("Include Images")
                                    Image(systemName: "photo")
                                        .foregroundColor(includeImages ? .accentColor : .secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    // Imports/Exports sections with consistent height
                    GroupBox(label: Text("Imports from:")) {
                        ImportExportList(items: fileSystem.fileItems)
                            .frame(height: 120)
                    }
                    
                    GroupBox(label: Text("Exports to:")) {
                        ImportExportList(items: fileSystem.fileItems)
                            .frame(height: 120)
                    }
                    
                    // Summaries with consistent height
                    GroupBox(label: Text("Summaries:")) {
                        if fileSystem.savedSummaries.isEmpty {
                            ContentUnavailableView {
                                Label("No Summaries", systemImage: "doc.text.magnifyingglass")
                            } description: {
                                Text("Generate a summary to see it here")
                            }
                            .frame(height: 100)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(fileSystem.savedSummaries) { summary in
                                        HStack {
                                            Image(systemName: summary.isIncluded ? "checkmark.square.fill" : "square")
                                                .foregroundColor(summary.isIncluded ? .accentColor : .secondary)
                                                .onTapGesture {
                                                    fileSystem.toggleSummary(summary)
                                                }
                                            Text(summary.fileName)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .frame(height: 100)
                        }
                    }
                    
                    Spacer()
                    
                    // Output format
                    GroupBox(label: Text("Output Format")) {
                        Picker("Format", selection: $outputFormat) {
                            ForEach(ExportConfig.OutputFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 5)
                    }
                    
                    Button("Generate Export") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.text]
                        panel.nameFieldStringValue = "export-\(ISO8601DateFormatter().string(from: Date()))"
                        
                        switch outputFormat {
                        case .markdown:
                            panel.allowedContentTypes = [.text]
                            panel.nameFieldStringValue += ".md"
                        case .html:
                            panel.allowedContentTypes = [.html]
                            panel.nameFieldStringValue += ".html"
                        case .plainText:
                            panel.allowedContentTypes = [.text]
                            panel.nameFieldStringValue += ".txt"
                        }
                        
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                let content = fileSystem.generateExport(format: outputFormat)
                                try? content.write(to: url, atomically: true, encoding: .utf8)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(fileSystem.selectedFiles.isEmpty && fileSystem.savedSummaries.isEmpty)
                }
                .frame(width: 250)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .sheet(isPresented: $isEditingSummary) {
            SummaryEditView(
                summary: $editedSummary,
                onSave: {
                    if let summary = generatedSummary {
                        fileSystem.saveSummary(editedSummary, for: summary.fileName)
                    }
                    isEditingSummary = false
                },
                onCancel: {
                    isEditingSummary = false
                },
                onRetry: {
                    generateSummary()
                }
            )
            .frame(minWidth: 800, minHeight: 600)
        }
        .alert("No Files Selected", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func selectRootFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                fileSystem.loadDirectory(at: url)
            }
        }
    }
    
    private func generateSummary() {
        guard !fileSystem.selectedFiles.isEmpty else {
            alertMessage = "Please select one or more files to generate a summary."
            showAlert = true
            return
        }
        
        do {
            let selectedItems = Array(fileSystem.selectedFiles)
            var summary: SummaryGenerator.Summary
            
            if selectedItems.count == 1, let item = selectedItems.first, item.isDirectory {
                // Generate folder summary
                let content = fileSystem.getFolderSummary(for: item)
                summary = SummaryGenerator.Summary(
                    content: content,
                    analysis: "Folder analysis for \(item.name)",
                    fileName: item.name
                )
            } else {
                // Generate regular summary
                summary = try SummaryGenerator.generateSummary(
                    for: selectedItems.map { item in 
                        FileItem(
                            name: item.name, 
                            path: item.path, 
                            isDirectory: item.isDirectory,
                            isExcluded: item.isExcluded,
                            isSelected: item.isSelected,
                            children: item.children
                        )
                    },
                    additionalComments: additionalComments
                )
            }
            
            self.generatedSummary = summary
            self.editedSummary = summary.content
            self.isEditingSummary = true
            self.additionalComments = "" // Reset additional comments
        } catch {
            alertMessage = "Error generating summary: \(error.localizedDescription)"
            showAlert = true
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

struct FileTreeView: View {
    @ObservedObject var fileSystem: FileSystemModel
    var showHiddenFiles: Bool
    
    init(fileSystem: FileSystemModel, showHiddenFiles: Bool) {
        self.fileSystem = fileSystem
        self.showHiddenFiles = showHiddenFiles
    }
    
    var body: some View {
        List(fileSystem.fileItems.filter { showHiddenFiles || !$0.name.hasPrefix(".") }, children: \.children) { item in
            FileItemRow(item: item, toggleSelection: {
                fileSystem.toggleSelection(for: item)
                fileSystem.updatePreview()
            }, model: fileSystem)
            .id(item.id)
        }
        .listStyle(.sidebar)
    }
}

struct FileItemRow: View {
    let item: FileItem
    let toggleSelection: () -> Void
    @ObservedObject var model: FileSystemModel
    
    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                .foregroundColor(item.isExcluded ? .gray : (item.isDirectory ? .blue : .secondary))
            
            Text(item.name)
                .foregroundColor(item.isExcluded ? .gray : .primary)
            
            if !item.isExcluded {
                Spacer()
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { _ in toggleSelection() }
                ))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.previewFileContent(for: item)
        }
    }
}