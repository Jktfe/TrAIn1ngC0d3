import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @StateObject private var fileSystem = FileSystemModel()
    @State private var showHiddenFiles = false {
        didSet {
            fileSystem.config.showHiddenFiles = showHiddenFiles
            fileSystem.refreshFileList()
        }
    }
    @State private var includeImages = true
    @State private var outputFormat: ExportConfig.OutputFormat = .markdown
    @State private var showSummarySheet = false
    @State private var currentSummaryFileName = ""
    @State private var currentSummaryContent = ""
    @State private var isEditingSummary = false
    @State private var showImportDialog = false
    @State private var isGeneratingSummary = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with logo and actions
            HStack {
                if let logoImage = NSImage(named: "TrAIn1ngC0d3 Logo") {
                    Image(nsImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .padding(.trailing)
                }
                
                Button(action: selectRootFolder) {
                    Label("Select Root", systemImage: "folder.badge.plus")
                }
                .buttonStyle(Theme.BorderedButtonStyle())
                
                if let path = fileSystem.rootPath {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(Theme.textColor)
                }
                
                Spacer()
                
                Button(action: { showImportDialog = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(Theme.SecondaryButtonStyle())
            }
            .padding()
            .frame(height: 60)
            .background(Theme.backgroundColor)
            
            Divider()
            
            HSplitView {
                // Left panel: File browser
                VStack(alignment: .leading, spacing: 0) {
                    Text("Files and Folders")
                        .font(.headline)
                        .foregroundColor(Theme.primaryColor)
                        .padding()
                        .frame(height: 50)
                    
                    List(fileSystem.fileItems, children: \.children) { item in
                        FileItemRow(item: item, isSelected: fileSystem.selectedFiles.contains(item)) {
                            fileSystem.toggleSelection(for: item)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            fileSystem.previewFileContent(for: item)
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 250)
                .background(Theme.backgroundColor.opacity(0.5))
                
                // Center panel: Actions and Preview
                VStack(spacing: 0) {
                    // Actions
                    HStack {
                        Button("Generate Summary") {
                            isGeneratingSummary = true
                            Task {
                                let summary = await fileSystem.generateSummary(for: fileSystem.lastClickedFileContent)
                                currentSummaryFileName = fileSystem.lastClickedFileName
                                currentSummaryContent = summary
                                showSummarySheet = true
                                isGeneratingSummary = false
                            }
                        }
                        .buttonStyle(Theme.BorderedButtonStyle())
                        .disabled(fileSystem.lastClickedFileName.isEmpty || isGeneratingSummary)
                        
                        if isGeneratingSummary {
                            ProgressView()
                                .scaleEffect(0.5)
                                .padding(.leading, 5)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    
                    // Preview area
                    ScrollView {
                        if !fileSystem.lastClickedFileName.isEmpty {
                            GroupBox {
                                Text("File Preview: \(fileSystem.lastClickedFileName)")
                                    .foregroundColor(Theme.primaryColor)
                                    .font(.headline)
                                Text(fileSystem.lastClickedFileContent)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .foregroundColor(Theme.textColor)
                            }
                            .padding()
                        } else {
                            ContentUnavailableView {
                                Label("No Preview", systemImage: "doc.text")
                                    .foregroundColor(Theme.textColor.opacity(0.6))
                            } description: {
                                Text("Click a file to preview its contents")
                                    .foregroundColor(Theme.textColor.opacity(0.6))
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
                .frame(minWidth: 400)
                .background(Theme.backgroundColor)
                
                // Right panel: Options and Summaries
                VStack(spacing: 15) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show Hidden Files", isOn: $showHiddenFiles)
                                .tint(Theme.primaryColor)
                            
                            Toggle(isOn: $includeImages) {
                                Label("Include Images", systemImage: "photo")
                                    .foregroundColor(Theme.textColor)
                            }
                            .tint(Theme.primaryColor)
                        }
                        .padding(.vertical, 5)
                    }
                    .groupBoxStyle(CustomGroupBoxStyle())
                    
                    // Recent imports
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Imports")
                                .font(.headline)
                                .foregroundColor(Theme.primaryColor)
                            
                            if fileSystem.importedFiles.isEmpty {
                                Text("No recent imports")
                                    .foregroundColor(Theme.textColor.opacity(0.6))
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(fileSystem.importedFiles, id: \.self) { url in
                                            Text(url.lastPathComponent)
                                                .lineLimit(1)
                                                .foregroundColor(Theme.textColor)
                                        }
                                    }
                                }
                                .frame(height: 80)
                            }
                        }
                    }
                    .groupBoxStyle(CustomGroupBoxStyle())
                    
                    // Recent exports
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Exports")
                                .font(.headline)
                                .foregroundColor(Theme.primaryColor)
                            
                            if fileSystem.exportedFiles.isEmpty {
                                Text("No recent exports")
                                    .foregroundColor(Theme.textColor.opacity(0.6))
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(fileSystem.exportedFiles, id: \.self) { url in
                                            Text(url.lastPathComponent)
                                                .lineLimit(1)
                                                .foregroundColor(Theme.textColor)
                                        }
                                    }
                                }
                                .frame(height: 80)
                            }
                        }
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
                            
                            Picker("Format", selection: $outputFormat) {
                                ForEach(ExportConfig.OutputFormat.allCases, id: \.self) { format in
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
                        let summary = await fileSystem.generateSummary(for: fileSystem.lastClickedFileContent)
                        currentSummaryContent = summary
                        isGeneratingSummary = false
                    }
                }
            )
            .frame(width: 800, height: 600)
        }
        .fileImporter(
            isPresented: $showImportDialog,
            allowedContentTypes: [.text],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                fileSystem.importFiles(from: urls)
            }
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
    
    private func exportContent(as format: ExportConfig.OutputFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "export-\(ISO8601DateFormatter().string(from: Date()))"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                let content = fileSystem.generateExport(format: format)
                try? content.write(to: url, atomically: true, encoding: .utf8)
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