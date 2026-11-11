import SwiftUI

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

extension CollapsibleSection where Footer == EmptyView {
    init(_ title: LocalizedStringKey, startOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, startOpen: startOpen, content: content, footer: { EmptyView() })
    }
}
