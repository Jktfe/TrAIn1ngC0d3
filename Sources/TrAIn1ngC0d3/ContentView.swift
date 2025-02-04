import SwiftUI
import AppKit
import Foundation

struct HeaderView: View {
    let onSelectRoot: () async -> Void
    
    var body: some View {
        HStack {
            Button(action: { Task { await onSelectRoot() } }) {
                HStack {
                    Image("TrAIn1ngC0d3_Logo_NoBackground")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                    Text("Select Root")
                        .foregroundColor(Theme.textColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.buttonGradient)
                )
            }
            .buttonStyle(.plain)
            
            if let path = UserDefaults.standard.string(forKey: "lastRootPath") {
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
    }
}

struct FileListView: View {
    @ObservedObject var fileSystem: FileSystemModel
    @Binding var selectedFiles: Set<FileItem>
    @Binding var currentSummaryContent: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files and Folders:")
                .font(.headline)
                .foregroundColor(Theme.primaryColor)
                .padding()
            
            List(selection: $selectedFiles) {
                ForEach(fileSystem.fileItems) { item in
                    FileItemRow(fileSystem: fileSystem,
                              item: item,
                              currentSummaryContent: $currentSummaryContent)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Theme.backgroundColor)
        .frame(width: 250)
    }
}

struct FileItemRow: View {
    @ObservedObject var fileSystem: FileSystemModel
    let item: FileItem
    @Binding var currentSummaryContent: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if item.isDirectory {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .foregroundColor(Theme.primaryColor)
                        .onTapGesture {
                            withAnimation {
                                isExpanded.toggle()
                            }
                        }
                } else {
                    Image(systemName: "doc")
                        .foregroundColor(Theme.primaryColor)
                        .padding(.leading, 4)
                }
                
                Text(item.name)
                    .foregroundColor(Theme.textColor)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { fileSystem.selectedFiles.contains(item) },
                    set: { _ in 
                        fileSystem.toggleSelection(for: item)
                        if fileSystem.selectedFiles.contains(item) {
                            Task {
                                fileSystem.currentItem = item
                                fileSystem.lastClickedFileName = item.name
                                fileSystem.lastClickedFilePath = item.path
                                
                                if item.isDirectory {
                                    if let summary = await fileSystem.generateDirectorySummary(for: item) {
                                        currentSummaryContent = summary
                                    }
                                } else if let content = try? String(contentsOfFile: item.path, encoding: .utf8) {
                                    fileSystem.lastClickedFileContent = content
                                    
                                    if let savedSummary = fileSystem.getSavedSummary(for: item.name) {
                                        currentSummaryContent = savedSummary
                                    } else {
                                        currentSummaryContent = await fileSystem.generateSummary(for: URL(fileURLWithPath: item.path), content: content)
                                        fileSystem.saveSummary(currentSummaryContent, for: item.name)
                                    }
                                    
                                    fileSystem.analyzeFileImportsAndExports(content, filePath: item.path)
                                }
                            }
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.primaryColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(fileSystem.currentItem?.id == item.id ? Theme.primaryColor.opacity(0.1) : Color.clear)
            .onTapGesture {
                Task {
                    fileSystem.currentItem = item
                    fileSystem.lastClickedFileName = item.name
                    fileSystem.lastClickedFilePath = item.path
                    
                    if item.isDirectory {
                        if let summary = await fileSystem.generateDirectorySummary(for: item) {
                            currentSummaryContent = summary
                        }
                    } else if let content = try? String(contentsOfFile: item.path, encoding: .utf8) {
                        fileSystem.lastClickedFileContent = content
                        
                        if let savedSummary = fileSystem.getSavedSummary(for: item.name) {
                            currentSummaryContent = savedSummary
                        } else {
                            currentSummaryContent = await fileSystem.generateSummary(for: URL(fileURLWithPath: item.path), content: content)
                            fileSystem.saveSummary(currentSummaryContent, for: item.name)
                        }
                        
                        fileSystem.analyzeFileImportsAndExports(content, filePath: item.path)
                    }
                }
            }
            
            if item.isDirectory && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileItemRow(fileSystem: fileSystem,
                              item: child,
                              currentSummaryContent: $currentSummaryContent)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

struct FilePreviewView: View {
    @ObservedObject var fileSystem: FileSystemModel
    let filePath: String
    @Binding var currentSummaryContent: String
    @State private var isEditing = false
    @State private var fileContent: String = ""
    
    var body: some View {
        VStack {
            ScrollView {
                if let url = URL(string: "file://" + filePath) {
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("Unable to load file content")
                            .foregroundColor(Theme.errorColor)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if let url = URL(string: "file://" + filePath),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                fileContent = content
                fileSystem.lastClickedFileContent = content
                fileSystem.lastClickedFilePath = filePath
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var fileSystem = FileSystemModel()
    @State private var selectedFiles: Set<FileItem> = []
    @State private var currentSummaryContent: String = ""
    @State private var showHiddenFiles = false
    @State private var includeImages = true
    @State private var outputFormat = "Markdown"
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onSelectRoot: fileSystem.selectRootDirectory)
            
            HSplitView {
                // Left panel - File Browser
                VStack(spacing: 0) {
                    FileListView(fileSystem: fileSystem,
                               selectedFiles: $selectedFiles,
                               currentSummaryContent: $currentSummaryContent)
                    
                    // Selected Files Section
                    if !selectedFiles.isEmpty {
                        GroupBox("Selected Files") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(selectedFiles), id: \.path) { file in
                                        Text(file.name)
                                            .foregroundColor(Theme.textColor)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(height: 100)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
                .frame(width: 250)
                .background(Theme.backgroundColor)
                
                // Center panel - File Preview and Dependencies
                if let selectedFile = selectedFiles.first {
                    VStack(spacing: 0) {
                        // File Preview
                        GroupBox("File Preview: \(selectedFile.name)") {
                            FilePreviewView(fileSystem: fileSystem,
                                          filePath: selectedFile.path,
                                          currentSummaryContent: $currentSummaryContent)
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Dependencies Section
                        HStack(spacing: 16) {
                            // Imports
                            GroupBox("Imports from:") {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let imports = fileSystem.fileImports[selectedFile.path] {
                                            ForEach(Array(imports).sorted(), id: \.self) { imp in
                                                Text(imp)
                                                    .foregroundColor(Theme.textColor)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Exports
                            GroupBox("Exports to:") {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let exports = fileSystem.fileExports[selectedFile.path] {
                                            ForEach(Array(exports).sorted(), id: \.self) { exp in
                                                Text(exp)
                                                    .foregroundColor(Theme.textColor)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 150)
                        .padding()
                    }
                } else {
                    Text("Select a file to preview")
                        .foregroundColor(Theme.secondaryTextColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Right panel - Export Options
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Content Options") {
                        VStack(alignment: .leading) {
                            Toggle("Show Hidden Files", isOn: $showHiddenFiles)
                                .onChange(of: showHiddenFiles) { newValue in
                                    fileSystem.config.showHiddenFiles = newValue
                                }
                            Toggle("Include Images", isOn: $includeImages)
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Output Format") {
                        Picker("Format", selection: $outputFormat) {
                            Text("Markdown").tag("Markdown")
                            Text("HTML").tag("HTML")
                            Text("Plain Text").tag("Plain Text")
                        }
                        .pickerStyle(.radioGroup)
                        .padding(8)
                    }
                    
                    Button(action: {
                        // Generate Summary action
                    }) {
                        Text("Generate Summary")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.buttonGradient)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(width: 200)
                .padding()
                .background(Theme.backgroundColor)
            }
        }
        .background(Theme.darkBackgroundColor)
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
                
                Button("Generate New Summary") {
                    Task {
                        guard let filePath = fileSystem.lastClickedFilePath,
                              let fileName = fileSystem.lastClickedFileName else {
                            return
                        }
                        let newSummary = await fileSystem.generateSummary(for: URL(fileURLWithPath: filePath), content: fileSystem.lastClickedFileContent)
                        summaryContent = newSummary
                        fileSystem.saveSummary(newSummary, for: fileName)
                        isEditing = true
                    }
                }
                
                if !isEditing {
                    Button("Retry with Comments") {
                        Task {
                            guard let filePath = fileSystem.lastClickedFilePath,
                                  let fileName = fileSystem.lastClickedFileName else {
                                return
                            }
                            // Use the content with comments preserved
                            let newSummary = await fileSystem.generateSummary(for: URL(fileURLWithPath: filePath), content: fileSystem.lastClickedFileContent)
                            summaryContent = newSummary
                            fileSystem.saveSummary(newSummary, for: fileName)
                            isEditing = true
                        }
                    }
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

extension Theme {
    struct SecondaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(backgroundColor)
                .foregroundColor(primaryColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(primaryColor.opacity(0.5), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }
    
    struct BorderedButtonStyle: ButtonStyle {
        let isSelected: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? primaryColor.opacity(0.1) : backgroundColor)
                .foregroundColor(primaryColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(primaryColor.opacity(0.5), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }
}