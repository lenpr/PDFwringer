import SwiftUI
import PDFKit

struct PageThumbnailStripView: View {
    let document: PDFDocument
    var currentPage: Binding<Int>?
    var selectedPages: Binding<Set<Int>>?
    var selectable: Bool { selectedPages != nil }

    private let thumbWidth: CGFloat = 48
    private let thumbHeight: CGFloat = 64

    @State private var cache = ThumbnailCache()
    @State private var zoomedPage: Int?

    var body: some View {
        VStack(spacing: 0) {
            if document.pageCount > 20 {
                HStack {
                    Spacer()
                    Text("Page \((currentPage?.wrappedValue ?? 0) + 1) of \(document.pageCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 6) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            thumbnailCell(index: index)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: currentPage?.wrappedValue) { _, newValue in
                    if let page = newValue {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(page, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: thumbHeight + (document.pageCount > 20 ? 48 : 28))
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .background {
            Group {
                Button("") { navigatePage(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("") { navigatePage(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                if selectable {
                    Button("") { toggleCurrentPageSelection() }
                        .keyboardShortcut(.return, modifiers: .option)
                }
            }
            .hidden()
        }
    }

    private func thumbnailCell(index: Int) -> some View {
        let isSelected = selectedPages?.wrappedValue.contains(index) ?? false
        let isCurrent = currentPage?.wrappedValue == index
        let _ = cache.generation

        return VStack(spacing: 3) {
            Group {
                if let img = cache.thumbnail(for: index, document: document, size: CGSize(width: thumbWidth * 2, height: thumbHeight * 2)) {
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
                    .strokeBorder(
                        isSelected ? Color.accentColor : (isCurrent ? Color.primary.opacity(0.5) : Color(nsColor: .separatorColor)),
                        lineWidth: isSelected ? 2 : (isCurrent ? 1.5 : 0.5)
                    )
            }
            .opacity(selectable && !isSelected && !isCurrent ? 0.7 : 1.0)
            .shadow(color: Color(nsColor: .shadowColor).opacity(isCurrent ? 0.2 : 0.1), radius: isCurrent ? 3 : 1, y: 1)
            .scaleEffect(isCurrent ? 1.08 : 1.0)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: currentPage?.wrappedValue)

            Text("\(index + 1)")
                .font(.system(size: 9, weight: isSelected || isCurrent ? .bold : .regular))
                .foregroundStyle(isSelected || isCurrent ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .help(tooltipForPage(at: index))
        .onTapGesture(count: 2) {
            zoomedPage = index
        }
        .onTapGesture {
            currentPage?.wrappedValue = index
            if selectable {
                if selectedPages!.wrappedValue.contains(index) {
                    selectedPages!.wrappedValue.remove(index)
                } else {
                    selectedPages!.wrappedValue.insert(index)
                }
            }
        }
        .popover(isPresented: Binding(get: { zoomedPage == index }, set: { if !$0 { zoomedPage = nil } })) {
            if let page = document.page(at: index) {
                let size = page.bounds(for: .cropBox).size
                let scale = min(400 / size.width, 500 / size.height)
                Image(nsImage: page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .cropBox))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 500)
                    .padding(8)
            }
        }
    }

    private func tooltipForPage(at index: Int) -> String {
        guard let page = document.page(at: index) else {
            return "Page \(index + 1)"
        }
        let box = page.bounds(for: .cropBox)
        let w = Int(box.width)
        let h = Int(box.height)
        return "Page \(index + 1) — \(w) × \(h) pt"
    }

    private func navigatePage(by offset: Int) {
        guard let binding = currentPage else { return }
        let newPage = binding.wrappedValue + offset
        guard newPage >= 0 && newPage < document.pageCount else { return }
        binding.wrappedValue = newPage
    }

    private func toggleCurrentPageSelection() {
        guard let pageBinding = currentPage, let selBinding = selectedPages else { return }
        let index = pageBinding.wrappedValue
        if selBinding.wrappedValue.contains(index) {
            selBinding.wrappedValue.remove(index)
        } else {
            selBinding.wrappedValue.insert(index)
        }
    }
}

@MainActor @Observable
final class ThumbnailCache {
    private let cache = NSCache<NSNumber, NSImage>()
    private var pending = Set<Int>()
    var generation = 0

    init() {
        cache.countLimit = 200
    }

    func thumbnail(for index: Int, document: PDFDocument, size: CGSize) -> NSImage? {
        let key = NSNumber(value: index)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard !pending.contains(index) else { return nil }
        pending.insert(index)

        let cache = self.cache
        Task.detached(priority: .utility) {
            guard let page = document.page(at: index) else { return }
            let img = page.thumbnail(of: size, for: .cropBox)
            await MainActor.run {
                cache.setObject(img, forKey: key)
                self.pending.remove(index)
                self.generation += 1
            }
        }

        return nil
    }
}
