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
                    
                    List(fileSystem.fileItems) { item in
                        FileItemRow(item: item, isSelected: fileSystem.selectedFiles.contains(item)) {
                            fileSystem.toggleSelection(for: item)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                fileSystem.lastClickedFileName = item.name
                                fileSystem.lastClickedFilePath = item.path
                                if let content = try? String(contentsOfFile: item.path, encoding: .utf8) {
                                    fileSystem.lastClickedFileContent = content
                                    
                                    // Try to load saved summary first
                                    if let savedSummary = fileSystem.getSavedSummary(for: item.name) {
                                        currentSummaryContent = savedSummary
                                    } else {
                                        // Generate new summary if none exists
                                        currentSummaryContent = await fileSystem.generateSummary(for: URL(fileURLWithPath: item.path), content: content)
                                        fileSystem.saveSummary(currentSummaryContent, for: item.name)
                                    }
                                    
                                    fileSystem.analyzeFileImportsAndExports(content, filePath: item.path)
                                }
                            }
                            selectedFile = item
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 250)
                .background(Theme.backgroundColor.opacity(0.5))
                
                // Middle panel: File preview and analysis
                VStack(spacing: 15) {
                    if let filePath = fileSystem.lastClickedFileName {
                        Button("Generate Summary") {
                            isGeneratingSummary = true
                            Task {
                                let summary = await fileSystem.generateSummary(for: URL(fileURLWithPath: filePath), content: fileSystem.lastClickedFileContent)
                                currentSummaryContent = summary
                                currentSummaryFileName = filePath
                                showSummarySheet = true
                                isGeneratingSummary = false
                            }
                        }
                        .buttonStyle(Theme.BorderedButtonStyle())
                        .disabled(isGeneratingSummary)
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("File Preview: \(filePath)")
                                        .font(.headline)
                                        .foregroundColor(Theme.primaryColor)
                                    
                                    Spacer()
                                    
                                    Toggle("Show Comments", isOn: $fileSystem.showComments)
                                        .toggleStyle(SwitchToggleStyle(tint: Theme.primaryColor))
                                }
                                
                                ScrollView {
                                    Text(fileSystem.showComments ? fileSystem.lastClickedFileContent : fileSystem.stripComments(from: fileSystem.lastClickedFileContent))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 200)
                            }
                            .padding()
                        }
                        .groupBoxStyle(CustomGroupBoxStyle())
                        
                        HStack(spacing: 15) {
                            importsFromSection
                            exportsToSection
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
            EditSummaryView(fileSystem: fileSystem, isPresented: $showSummarySheet, summaryContent: $currentSummaryContent)
                .frame(width: 800, height: 600)
        }
    }
    
    var importsFromSection: some View {
        GroupBox(label: Text("Imports From").bold()) {
            if let filePath = fileSystem.lastClickedFileName,
               let imports = fileSystem.fileImports[filePath],
               !imports.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(imports).sorted(), id: \.self) { importName in
                            Text(importName)
                                .foregroundColor(Theme.textColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No imports found")
                    .foregroundColor(Theme.textColor)
                    .italic()
            }
        }
        .groupBoxStyle(TransparentGroupBox())
    }
    
    var exportsToSection: some View {
        GroupBox(label: Text("Exports To").bold()) {
            if let filePath = fileSystem.lastClickedFileName,
               let exports = fileSystem.fileExports[filePath],
               !exports.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(exports).sorted(), id: \.self) { exportName in
                            Text(exportName)
                                .foregroundColor(Theme.textColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No exports found")
                    .foregroundColor(Theme.textColor)
                    .italic()
            }
        }
        .groupBoxStyle(TransparentGroupBox())
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

struct EditSummaryView: View {
    @ObservedObject var fileSystem: FileSystemModel
    @Binding var isPresented: Bool
    @Binding var summaryContent: String
    @State private var editedContent: String = ""
    @State private var additionalComments: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Summary")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    isPresented = false
                }
            }
            .padding(.bottom)
            
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.borderColor, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    Text(summaryContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Theme.backgroundColor)
                        .cornerRadius(8)
                }
                .frame(minHeight: 300)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Additional Comments")
                    .font(.headline)
                TextEditor(text: $additionalComments)
                    .font(.system(.body))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.borderColor, lineWidth: 1)
                    )
            }
            
            HStack {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        fileSystem.saveSummary(editedContent, for: fileSystem.lastClickedFileName ?? "")
                        summaryContent = editedContent
                        isEditing = false
                    } else {
                        editedContent = summaryContent
                        isEditing = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                
                if !isEditing {
                    Button("Retry with Comments") {
                        Task {
                            if let fileName = fileSystem.lastClickedFileName,
                               let filePath = fileSystem.lastClickedFilePath,
                               let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                                let newSummary = await fileSystem.generateSummary(for: URL(fileURLWithPath: filePath), content: content)
                                fileSystem.saveSummary(newSummary, for: fileName)
                                summaryContent = newSummary
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            editedContent = summaryContent
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

struct TransparentGroupBox: GroupBoxStyle {
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
                .fill(Color.clear)
                .shadow(color: Color.clear, radius: 0, x: 0, y: 0)
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.primaryColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.backgroundColor)
            .foregroundColor(Theme.primaryColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.primaryColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}