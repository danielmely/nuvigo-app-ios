import WidgetKit
import SwiftUI
import ActivityKit

// The NuviGoWidgets extension. In Xcode: File > New > Target > Widget Extension (tick "Include Live Activity",
// untick "Include Configuration App Intent"), delete the generated files, then add this file to that target,
// plus SharedSnapshot.swift and DownloadActivity.swift (tick both targets for those two).

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private func poster(_ file: String?) -> UIImage? {
    guard let file, let url = NuviGoShared.postersDir?.appendingPathComponent(file) else { return nil }
    return UIImage(contentsOfFile: url.path)
}

private let accent = Color(red: 0.49, green: 0.30, blue: 0.95)

private struct PosterView: View {
    let item: WidgetContinueItem
    var body: some View {
        ZStack {
            if let img = poster(item.posterFile) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [accent.opacity(0.7), .black], startPoint: .top, endPoint: .bottom)
                Image(systemName: "film").font(.title).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Continue Watching

struct ContinueWatchingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var items: [WidgetContinueItem] { entry.snapshot.continueWatching }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(accent)
                Text("Nothing in progress").font(.footnote.weight(.semibold))
                Text("Start something in NuviGo").font(.caption2).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        } else if family == .systemSmall {
            small(items[0])
        } else {
            HStack(spacing: 10) {
                ForEach(items.prefix(3)) { cell($0) }
            }
        }
    }

    private func small(_ it: WidgetContinueItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(item: it).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(it.name).font(.caption.weight(.bold)).lineLimit(2)
                if let l = it.episodeLabel { Text(l).font(.caption2).opacity(0.8) }
                ProgressView(value: it.fraction).tint(accent)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .widgetURL(NuviGoShared.titleLink(type: it.type, id: it.id, name: it.name))
    }

    private func cell(_ it: WidgetContinueItem) -> some View {
        Link(destination: NuviGoShared.titleLink(type: it.type, id: it.id, name: it.name)) {
            VStack(alignment: .leading, spacing: 4) {
                PosterView(item: it)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                ProgressView(value: it.fraction).tint(accent)
                Text(it.name).font(.caption2.weight(.semibold)).lineLimit(1)
            }
        }
    }
}

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NuviGoContinue", provider: SnapshotProvider()) { entry in
            ContinueWatchingView(entry: entry).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Upcoming episodes

struct UpcomingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        let list = Array(entry.snapshot.upcoming.prefix(family == .systemSmall ? 3 : 4))
        VStack(alignment: .leading, spacing: 6) {
            Label("Coming up", systemImage: "calendar").font(.caption.weight(.bold)).foregroundStyle(accent)
            if list.isEmpty {
                Spacer()
                Text("No new episodes soon for the shows you follow on Trakt.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(list) { u in
                    Link(destination: NuviGoShared.titleLink(type: "series", id: u.imdb, name: u.show)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(u.show).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(u.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(day(u.airs)).font(.caption2.weight(.semibold))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NuviGoUpcoming", provider: SnapshotProvider()) { entry in
            UpcomingView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Coming Up")
        .description("New episodes of the shows you follow.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Download Live Activity

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
                    Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if context.state.total > 1 {
                        Text("\(min(context.state.finished + 1, context.state.total)) of \(context.state.total)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: context.state.progress).tint(accent)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.8))
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent).font(.title2) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(Int(context.state.progress * 100))%").font(.title3.weight(.bold)) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).lineLimit(1).font(.subheadline) }
                DynamicIslandExpandedRegion(.bottom) { ProgressView(value: context.state.progress).tint(accent) }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%").font(.caption2.weight(.bold))
            } minimal: {
                Image(systemName: "arrow.down").foregroundStyle(accent)
            }
        }
    }
}

// MARK: - Bundle

@main
struct NuviGoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
        UpcomingWidget()
        DownloadLiveActivity()
    }
}
