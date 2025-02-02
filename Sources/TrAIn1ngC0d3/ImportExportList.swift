import SwiftUI

struct ImportExportList: View {
    let items: [FileItem]
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    if item.isDirectory {
                        HStack {
                            Image(systemName: "folder")
                            Text(item.name)
                        }
                        if let children = item.children {
                            ImportExportList(items: children)
                                .padding(.leading)
                        }
                    } else {
                        HStack {
                            Image(systemName: "doc")
                            Text(item.name)
                        }
                    }
                }
            }
        }
    }
}
