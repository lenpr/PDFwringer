import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Compress", systemImage: "arrow.down.doc") {
                CompressView()
            }
            Tab("Concatenate", systemImage: "doc.on.doc") {
                ConcatenateView()
            }
            Tab("Split / Extract", systemImage: "scissors") {
                SplitView()
            }
        }
        .frame(minWidth: 650, minHeight: 420)
    }
}
