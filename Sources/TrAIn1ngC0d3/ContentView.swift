import SwiftUI
import AppKit
import Foundation

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(Theme.primaryColor)
            Text("TrAIn1ngC0d3")
                .font(.title)
                .foregroundColor(Theme.primaryColor)
        }
        .padding()
    }
}

struct FileListView: View {
    @ObservedObject var fileSystem: FileSystemModel
    @Binding var selectedFiles: Set<FileItem>
    @Binding var currentSummaryContent: String
    
    var body: some View {
        List(fileSystem.fileItems) { item in
            FileItemRow(item: item, isSelected: selectedFiles.contains(item)) {
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
            }
        }
    }
}

struct FilePreviewView: View {
    @ObservedObject var fileSystem: FileSystemModel
    let filePath: String
    
    var body: some View {
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
    }
}

struct ImportsExportsView: View {
    let imports: Set<String>
    let exports: Set<String>
    let filePath: String
    
    var body: some View {
        HStack(spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Imports From")
                        .font(.headline)
                        .foregroundColor(Theme.primaryColor)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(imports).sorted(), id: \.self) { imp in
                                Text(imp)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exports To")
                        .font(.headline)
                        .foregroundColor(Theme.primaryColor)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(exports).sorted(), id: \.self) { exp in
                                Text(exp)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .groupBoxStyle(CustomGroupBoxStyle())
    }
}

struct ContentView: View {
    @StateObject var fileSystem = FileSystemModel()
    @State private var selectedFiles: Set<FileItem> = []
    @State private var showSummarySheet = false
    @State private var currentSummaryContent: String = ""
    @State private var selectedFile: FileItem = FileItem(name: "", path: "", isDirectory: false)
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            
            HSplitView {
                VStack {
                    FileListView(fileSystem: fileSystem, 
                               selectedFiles: $selectedFiles,
                               currentSummaryContent: $currentSummaryContent)
                }
                .frame(minWidth: 200, maxWidth: .infinity)
                
                VStack(spacing: 20) {
                    if let filePath = fileSystem.lastClickedFilePath {
                        FilePreviewView(fileSystem: fileSystem, filePath: filePath)
                        
                        if let imports = fileSystem.fileImports[filePath],
                           let exports = fileSystem.fileExports[filePath] {
                            ImportsExportsView(imports: imports, exports: exports, filePath: filePath)
                        }
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Code Summary")
                                        .font(.headline)
                                        .foregroundColor(Theme.primaryColor)
                                    
                                    Spacer()
                                    
                                    Button("Edit") {
                                        showSummarySheet = true
                                    }
                                }
                                
                                ScrollView {
                                    Text(currentSummaryContent)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 200)
                            }
                            .padding()
                        }
                        .groupBoxStyle(CustomGroupBoxStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .sheet(isPresented: $showSummarySheet) {
            EditSummaryView(fileSystem: fileSystem, isPresented: $showSummarySheet, summaryContent: $currentSummaryContent)
                .frame(width: 800, height: 600)
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