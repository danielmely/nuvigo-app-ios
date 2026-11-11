import SwiftUI
import Charts

/// How much you watch. Kept on this device only (per profile) and never uploaded. Private mode records nothing.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    struct Totals: Codable {
        var days: [String: Double] = [:]      // "2026-11-10" -> seconds watched
        var genres: [String: Double] = [:]    // genre -> seconds
        var movieSeconds = 0.0
        var showSeconds = 0.0
        var since = Date()
    }

    @Published private(set) var totals = Totals()
    private var key: String { "watchStats" + ProfileStore.suffix }
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private init() { reload() }

    /// Re-reads this profile's numbers (after switching profile).
    func reload() {
        if let data = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode(Totals.self, from: data) {
            totals = t
        } else { totals = Totals() }
    }

    func clearAll() {
        totals = Totals()
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Called by ProgressStore while something plays.
    func record(seconds: Double, item: MetaItem) {
        guard seconds > 0, !PrivateMode.isOn else { return }
        let day = Self.dayFormat.string(from: Date())
        totals.days[day, default: 0] += seconds
        if item.type == "movie" { totals.movieSeconds += seconds } else { totals.showSeconds += seconds }
        let list = (item.genres ?? []).prefix(3)
        for g in list { totals.genres[g, default: 0] += seconds / Double(list.count) }
        if let data = try? JSONEncoder().encode(totals) { UserDefaults.standard.set(data, forKey: key) }
    }

    // MARK: Numbers for the screen

    var totalSeconds: Double { totals.movieSeconds + totals.showSeconds }

    func seconds(on date: Date) -> Double { totals.days[Self.dayFormat.string(from: date)] ?? 0 }

    /// Last `n` days, oldest first.
    func recentDays(_ n: Int) -> [(date: Date, minutes: Double)] {
        let cal = Calendar.current
        return (0..<n).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: Date())) else { return nil }
            return (d, seconds(on: d) / 60)
        }
    }

    var weekSeconds: Double { recentDays(7).reduce(0) { $0 + $1.minutes * 60 } }

    /// A day counts toward a streak once you've watched at least 5 minutes.
    private static let streakMinimum = 300.0

    var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if seconds(on: day) < Self.streakMinimum { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }   // today can still be saved
        var n = 0
        while seconds(on: day) >= Self.streakMinimum {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    var bestStreak: Int {
        let cal = Calendar.current
        let days = totals.days.filter { $0.value >= Self.streakMinimum }.keys
            .compactMap { Self.dayFormat.date(from: $0) }.sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p).map({ cal.isDate($0, inSameDayAs: d) }) == true { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }

    var topGenres: [(name: String, seconds: Double)] {
        totals.genres.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }
}

func statsDuration(_ seconds: Double) -> String {
    let m = Int(seconds / 60)
    if m < 60 { return "\(m) min" }
    let h = Double(m) / 60
    return h >= 100 ? "\(Int(h)) h" : String(format: "%.1f h", h)
}

/// The Account row that opens the stats page.
struct StatsLinkSection: View {
    var body: some View {
        Section {
            NavigationLink { StatsView() } label: {
                Label("Your stats", systemImage: "chart.bar.fill")
            }
        }
    }
}

struct StatsView: View {
    @ObservedObject private var stats = StatsStore.shared
    @EnvironmentObject var watched: WatchedStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    tile("Total", statsDuration(stats.totalSeconds), "clock")
                    tile("This week", statsDuration(stats.weekSeconds), "calendar")
                }
                HStack(spacing: 12) {
                    tile("Streak", "\(stats.currentStreak) day\(stats.currentStreak == 1 ? "" : "s")", "flame.fill")
                    tile("Best streak", "\(stats.bestStreak) day\(stats.bestStreak == 1 ? "" : "s")", "trophy.fill")
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Last 14 days") {
                Chart(stats.recentDays(14), id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Minutes", d.minutes))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { AxisValueLabel(format: .dateTime.day()) } }
                .frame(height: 150)
                .accessibilityLabel("Minutes watched per day for the last 14 days")
            }

            if !stats.topGenres.isEmpty {
                Section("Top genres") {
                    let top = stats.topGenres.first?.seconds ?? 1
                    ForEach(stats.topGenres, id: \.name) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(g.name); Spacer(); Text(statsDuration(g.seconds)).foregroundStyle(.secondary) }
                            ProgressView(value: g.seconds, total: top).tint(Theme.accent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Movies and shows") {
                let total = max(stats.totalSeconds, 1)
                row("Movies", statsDuration(stats.totals.movieSeconds), stats.totals.movieSeconds / total)
                row("Shows", statsDuration(stats.totals.showSeconds), stats.totals.showSeconds / total)
            }

            Section("Your library") {
                HStack { Text("Titles marked watched"); Spacer(); Text("\(watched.items.count)").foregroundStyle(.secondary) }
                let rated = watched.items.compactMap(\.rating)
                if !rated.isEmpty {
                    HStack { Text("Average rating"); Spacer()
                        Text(String(format: "%.1f / 10", Double(rated.reduce(0, +)) / Double(rated.count))).foregroundStyle(.secondary) }
                }
            }

            Section {
                Text("Stats are saved only on this device for this profile, and you can clear them with Clear my data. Nothing is recorded in Private mode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Your stats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { stats.reload() }
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
            ProgressView(value: fraction).tint(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}
