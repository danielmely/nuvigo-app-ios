import SwiftUI
import Combine

/// A List section whose title has a chevron. Tap the title to open or close it.
struct CollapsibleSection<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    @State private var open: Bool
    private let content: Content
    private let footer: Footer

    init(_ title: LocalizedStringKey, startOpen: Bool = false,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        _open = State(initialValue: startOpen)
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        Section {
            if open { content }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.vertical, 4)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(open ? "collapse" : "expand")")
        } footer: {
            if open { footer }
        }
    }
}

/// A smaller dropdown that sits inside the rows of a CollapsibleSection. Tap the title to open or close it.
/// It adds rows to the section it is in, so it never creates a second section.
struct SubGroup<Content: View>: View {
    let title: LocalizedStringKey
    @State private var open = false
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
        } label: {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(open ? "collapse" : "expand")")
        if open { content }
    }
}

extension CollapsibleSection where Footer == EmptyView {
    init(_ title: LocalizedStringKey, startOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, startOpen: startOpen, content: content, footer: { EmptyView() })
    }
}
