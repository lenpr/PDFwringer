import SwiftUI
import PDFKit

struct PageThumbnailStripView: View {
    let document: PDFDocument
    var selectedPages: Binding<Set<Int>>?
    var selectable: Bool { selectedPages != nil }

    private let thumbWidth: CGFloat = 48
    private let thumbHeight: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 6) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    thumbnailCell(index: index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: thumbHeight + 28)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func thumbnailCell(index: Int) -> some View {
        let isSelected = selectedPages?.wrappedValue.contains(index) ?? false

        return VStack(spacing: 3) {
            Group {
                if let page = document.page(at: index) {
                    let img = page.thumbnail(of: CGSize(width: thumbWidth * 2, height: thumbHeight * 2), for: .cropBox)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 0.5)
            }
            .opacity(selectable && !isSelected ? 0.7 : 1.0)
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.1), radius: 1, y: 1)

            Text("\(index + 1)")
                .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectable else { return }
            if selectedPages!.wrappedValue.contains(index) {
                selectedPages!.wrappedValue.remove(index)
            } else {
                selectedPages!.wrappedValue.insert(index)
            }
        }
    }
}
