import SwiftUI

struct SummaryEditView: View {
    @Binding var summary: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    @State private var additionalComments: String = ""
    @State private var selectedSection: Int? = nil
    @FocusState private var isSummaryFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Edit Summary")
                    .font(.headline)
                Spacer()
                Button("Close", action: onCancel)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            HSplitView {
                // Main summary editor
                VStack(spacing: 0) {
                    // Editor toolbar
                    HStack {
                        Button(action: { isSummaryFocused = true }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button(action: onSave) {
                            Label("Save", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    
                    // Editor
                    TextEditor(text: $summary)
                        .font(.system(.body, design: .monospaced))
                        .focused($isSummaryFocused)
                        .textSelection(.enabled)
                }
                .frame(minWidth: 500)
                
                // Right panel
                VStack(spacing: 15) {
                    // Section navigator
                    GroupBox("Sections") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(getSections(), id: \.offset) { section in
                                    Button(action: { scrollToSection(section) }) {
                                        Text(section.title)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(selectedSection == section.offset ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    
                    // Additional comments for retry
                    GroupBox("Additional Comments") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $additionalComments)
                                .font(.body)
                                .frame(height: 100)
                            
                            Button(action: {
                                onRetry()
                                additionalComments = ""
                            }) {
                                Label("Retry with Comments", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(additionalComments.isEmpty)
                        }
                    }
                }
                .frame(width: 250)
                .padding()
            }
        }
    }
    
    private struct Section {
        let title: String
        let offset: Int
    }
    
    private func getSections() -> [Section] {
        var sections: [Section] = []
        var currentOffset = 0
        
        let lines = summary.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#") {
                sections.append(Section(
                    title: line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")),
                    offset: index
                ))
            }
            currentOffset += line.count + 1 // +1 for newline
        }
        
        return sections
    }
    
    private func scrollToSection(_ section: Section) {
        selectedSection = section.offset
        // In a real app, we'd scroll to the section here
        // This would require a ScrollViewReader and id's for each section
    }
}
