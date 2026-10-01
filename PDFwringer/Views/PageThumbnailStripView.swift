import SwiftUI
import PDFKit

struct PageThumbnailStripView: View {
    @Environment(AppViewModel.self) private var appVM
    let document: PDFDocument
    var currentPage: Binding<Int>?
    var selectedPages: Binding<Set<Int>>?
    var selectable: Bool { selectedPages != nil }

    private let thumbWidth: CGFloat = 48
    private let thumbHeight: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .contentTransition(.numericText())
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
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(page, anchor: .center)
                        }
                    }
                }
            }
        }
        .onDisappear { cache.cancel() }
        .frame(height: thumbHeight + (document.pageCount > 20 ? 48 : 28))
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .background {
            Group {
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
                if let img = cache.thumbnail(for: index, document: document,
                                             size: CGSize(width: thumbWidth * 2, height: thumbHeight * 2),
                                             priority: isCurrent, sourceData: appVM.previewSourceData(for: document)) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ThumbnailPlaceholder()
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        isSelected ? Color.coral : (isCurrent ? Color.primary.opacity(0.5) : Color(nsColor: .separatorColor)),
                        lineWidth: isSelected ? 2 : (isCurrent ? 1.5 : 0.5)
                    )
            }
            .opacity(selectable && !isSelected && !isCurrent ? 0.7 : 1.0)
            .shadow(color: Color(nsColor: .shadowColor).opacity(isCurrent ? 0.2 : 0.1), radius: isCurrent ? 3 : 1, y: 1)
            .scaleEffect(isCurrent && !reduceMotion ? 1.04 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: currentPage?.wrappedValue)

            Text("\(index + 1)")
                .font(isSelected || isCurrent ? .caption2.bold() : .caption2)
                .foregroundStyle(isSelected || isCurrent ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .help(tooltipForPage(at: index))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityValue([isCurrent ? "Current" : "", isSelected ? "Selected" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .onTapGesture(count: 2) { zoomedPage = index }
        .onTapGesture { activatePage(index) }
        .focusable()
        .onKeyPress(keys: [.space, .return], phases: .down) { _ in
            activatePage(index)
            return .handled
        }
        .accessibilityAction { activatePage(index) }
        .accessibilityAction(named: Text("Show Preview")) { zoomedPage = index }
        .accessibilityActions {
            if selectable {
                Button(String(localized: "Toggle Selection")) { toggleSelection(index) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectable {
                Button { toggleSelection(index) } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.coralText : Color.primary)
                        .padding(4)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isSelected ? String(localized: "Exclude this page") : String(localized: "Include this page"))
                .accessibilityLabel("Select page \(index + 1)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .contextMenu {
            Button("Show Preview") { zoomedPage = index }
        }
        .popover(isPresented: Binding(get: { zoomedPage == index }, set: { if !$0 { zoomedPage = nil } })) {
            if let page = document.page(at: index) {
                let size = page.bounds(for: .cropBox).size
                let scale = min(400 / size.width, 500 / size.height)
                let previewSize = CGSize(width: size.width * scale, height: size.height * scale)
                if size.width > 0, size.height > 0,
                   previewSize.width.isFinite, previewSize.height.isFinite,
                   previewSize.width > 0, previewSize.height > 0 {
                    let _ = cache.generation
                    Group {
                        if let image = cache.thumbnail(for: index, document: document, size: previewSize, priority: true, sourceData: appVM.previewSourceData(for: document)) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: previewSize.width, height: previewSize.height)
                    .padding(8)
                } else {
                    Text(String(localized: "Preview unavailable for this page."))
                        .padding()
                }
            }
        }
        .onAppear {
            _ = cache.thumbnail(for: index, document: document,
                                size: CGSize(width: thumbWidth * 2, height: thumbHeight * 2), priority: isCurrent, sourceData: appVM.previewSourceData(for: document))
        }
        .onDisappear {
            cache.discardQueued(for: index, document: document,
                                size: CGSize(width: thumbWidth * 2, height: thumbHeight * 2))
        }
    }

    private func activatePage(_ index: Int) {
        currentPage?.wrappedValue = index
    }

    private func toggleSelection(_ index: Int) {
        guard let binding = selectedPages else { return }
        if binding.wrappedValue.contains(index) {
            binding.wrappedValue.remove(index)
        } else {
            binding.wrappedValue.insert(index)
        }
    }

    private func tooltipForPage(at index: Int) -> String {
        guard let page = document.page(at: index) else {
            return "Page \(index + 1)"
        }
        return Formatting.pageTooltip(
            pageNumber: index + 1,
            cropBox: page.bounds(for: .cropBox)
        )
    }

    private func toggleCurrentPageSelection() {
        guard let pageBinding = currentPage else { return }
        toggleSelection(pageBinding.wrappedValue)
    }
}

private struct ThumbnailPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay { Image(systemName: "doc").foregroundStyle(.tertiary) }
            .accessibilityHidden(true)
    }
}
