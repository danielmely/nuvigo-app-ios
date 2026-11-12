import SwiftUI
import Combine

struct CatalogRow: Identifiable {
    let id: String
    let title: String
    let type: String
    let items: [MetaItem]
}

/// A titled, horizontally scrolling row of posters.
struct PosterRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) { content() }.padding(.horizontal)
            }
        }
    }
}

struct PosterLink: View {
    let item: MetaItem
    @EnvironmentObject var trakt: TraktAuth

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: item.poster.flatMap(URL.init(string:))) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if item.type == "movie" && trakt.isWatched(item.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.title3)
                            .padding(6)
                            .accessibilityLabel("Watched")
                    }
                }
                Text(item.name).font(.caption).lineLimit(2).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        if trakt.isSignedIn, item.id.hasPrefix("tt") {
            if item.type == "movie" {
                let watched = trakt.isWatched(item.id)
                Button {
                    Task { await trakt.setWatched(!watched, type: item.type, id: item.id) }
                } label: {
                    Label(watched ? "Mark as unwatched" : "Mark as watched", systemImage: watched ? "eye.slash" : "eye")
                }
            } else {
                Button {
                    Task { await trakt.setWatched(true, type: item.type, id: item.id) }
                } label: { Label("Mark all episodes watched", systemImage: "eye") }
                Button(role: .destructive) {
                    Task { await trakt.setWatched(false, type: item.type, id: item.id) }
                } label: { Label("Clear watched history", systemImage: "eye.slash") }
            }
            let saved = trakt.isInWatchlist(item.id)
            Button {
                Task { await trakt.toggleWatchlist(type: item.type, id: item.id) }
            } label: {
                Label(saved ? "Remove from watchlist" : "Add to watchlist", systemImage: saved ? "bookmark.slash" : "bookmark")
            }
        }
    }
}

struct ContinueCard: View {
    let entry: WatchProgress
    @EnvironmentObject var progress: ProgressStore

    var body: some View {
        NavigationLink(value: entry.metaItem) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: entry.poster.flatMap(URL.init(string:))) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                ProgressView(value: entry.fraction)
                Text(entry.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
                if let label = entry.episodeLabel {
                    Text(SpoilerGuard.hide(label)).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name + (entry.episodeLabel.map { ", " + $0 } ?? ""))
        .accessibilityValue("\(Int(entry.fraction * 100)) percent watched")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(role: .destructive) { progress.clearTitle(entry.itemID) } label: {
                Label("Remove from Continue watching", systemImage: "xmark.circle")
            }
        }
    }
}

/// The first few browsable catalogs from your addons, shown as rows at the top of Browse.
enum HomeRows {
    static func load(_ addons: [Addon], limit: Int = 4) async -> [CatalogRow] {
        var targets: [(Addon, CatalogDecl)] = []
        for a in addons { for c in a.manifest.catalogs where c.isBrowsable { targets.append((a, c)) } }
        let picked = Array(targets.prefix(limit))
        var out: [(Int, CatalogRow)] = []
        await withTaskGroup(of: (Int, CatalogRow?).self) { group in
            for (i, target) in picked.enumerated() {
                group.addTask {
                    let (addon, cat) = target
                    guard let items = try? await AddonClient.catalog(addon, type: cat.type, id: cat.id), !items.isEmpty else { return (i, nil) }
                    return (i, CatalogRow(id: "\(addon.id)/\(cat.uid)",
                                          title: "\(cat.displayName) · \(cat.type.capitalized)",
                                          type: cat.type, items: Array(items.prefix(20))))
                }
            }
            for await (i, row) in group { if let row { out.append((i, row)) } }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

/// Trakt only knows ids, so titles and posters come from whichever addon serves metadata.
enum WatchlistLoader {
    static func load(_ entries: [TraktListEntry], addons: [Addon]) async -> [MetaItem] {
        var out: [(Int, MetaItem)] = []
        await withTaskGroup(of: (Int, MetaItem?).self) { group in
            for (i, e) in entries.prefix(40).enumerated() {
                group.addTask {
                    for addon in addons where addon.supports("meta", type: e.type, id: e.id) {
                        if let m = try? await AddonClient.meta(addon, type: e.type, id: e.id) { return (i, m) }
                    }
                    return (i, nil)
                }
            }
            for await (i, m) in group { if let m { out.append((i, m)) } }
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
