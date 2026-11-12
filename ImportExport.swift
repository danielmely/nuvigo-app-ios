import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - File formats

/// The NuviGo backup file: your add-ons plus everything you've watched and rated.
nonisolated struct BackupFile: Codable {
    var app = "NuviGo"
    var version = 1
    var exported = Date()
    var addons: [String]
    var watched: [WatchedItem]
}

/// One row read from a CSV, before it is matched to a title.
nonisolated struct ImportEntry: Sendable {
    var imdbID: String?
    var title: String
    var year: String?
    var rating: Int?        // 1...10
    var date: Date?
    var isSeries: Bool
}

nonisolated enum DataPortability {
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: Export

    static func backupData(addons: [String], watched: [WatchedItem]) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(BackupFile(addons: addons, watched: watched))
    }

    /// Letterboxd-style columns (plus the IMDb id), so it also opens in a spreadsheet.
    /// Rating is 0.5-5 like Letterboxd, so a 10 becomes 5.0.
    static func csv(watched: [WatchedItem]) -> Data {
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "imdbID,Title,Year,Rating,WatchedDate,Type\n"
        for w in watched {
            let rating = w.rating.map { String(format: "%.1f", Double($0) / 2) } ?? ""
            let date = w.date == .distantPast.addingTimeInterval(1) ? "" : dayFormat.string(from: w.date)
            out += [w.id, field(w.name), w.year ?? "", rating, date, w.type].joined(separator: ",") + "\n"
        }
        return Data(out.utf8)
    }

    // MARK: Import

    /// Reads a CSV into rows keyed by the lowercased header names. Handles quotes, commas and line breaks inside quotes.
    static func parseCSV(_ text: String) -> [[String: String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" { row.append(field); field = ""; rows.append(row); row = [] }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return [] }
        return rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { r in
            var d: [String: String] = [:]
            for (n, h) in header.enumerated() where n < r.count { d[h] = r[n].trimmingCharacters(in: .whitespaces) }
            return d
        }
    }

    /// Understands Letterboxd (watched.csv, ratings.csv), IMDb ratings exports and NuviGo's own CSV.
    static func entry(_ r: [String: String]) -> ImportEntry? {
        let title = r["title"] ?? r["name"] ?? ""
        guard !title.isEmpty else { return nil }
        let kind = (r["title type"] ?? r["type"] ?? "").lowercased()
        if kind.contains("episode") { return nil }

        let rawID = r["const"] ?? r["imdbid"] ?? r["imdb id"] ?? ""
        let imdb = rawID.hasPrefix("tt") ? rawID : nil

        var rating: Int?
        if let v = r["your rating"].flatMap(Double.init) { rating = Int(v.rounded()) }          // IMDb: 1-10
        else if let v = r["rating"].flatMap(Double.init) { rating = Int((v * 2).rounded()) }    // Letterboxd: 0.5-5
        rating = rating.map { min(max($0, 1), 10) }

        let dateText = r["watched date"] ?? r["watcheddate"] ?? r["date rated"] ?? r["date"] ?? ""
        let year = (r["year"] ?? r["release year"]).map { String($0.prefix(4)) }

        return ImportEntry(imdbID: imdb, title: title, year: year?.isEmpty == true ? nil : year, rating: rating,
                           date: dayFormat.date(from: String(dateText.prefix(10))),
                           isSeries: kind.contains("series") || kind == "tv")
    }

    /// Turns a row into a watched item. Rows with an IMDb id are used as they are;
    /// the rest are looked up on Cinemeta by title and year.
    static func item(for e: ImportEntry) async -> WatchedItem? {
        let type = e.isSeries ? "series" : "movie"
        let when = e.date ?? Date.distantPast.addingTimeInterval(1)
        if let id = e.imdbID {
            return WatchedItem(id: id, type: type, name: e.title, poster: nil, year: e.year, genres: [], rating: e.rating, date: when)
        }
        guard let m = await resolve(title: e.title, year: e.year, type: type) else { return nil }
        return WatchedItem(id: m.id, type: m.type, name: m.name, poster: m.poster,
                           year: m.releaseInfo.map { String($0.prefix(4)) } ?? e.year, genres: m.genres ?? [],
                           rating: e.rating, date: when)
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func resolve(title: String, year: String?, type: String) async -> MetaItem? {
        guard let url = URL(string: "https://v3-cinemeta.strem.io/catalog/\(type)/top/search=\(HTTP.encode(title)).json"),
              let (status, data) = try? await HTTP.send(url, timeout: 15), status == 200,
              let obj = HTTP.object(data), let metas = obj["metas"] as? [[String: Any]] else { return nil }
        let want = normalized(title)
        func yearOf(_ m: [String: Any]) -> String? { (m["releaseInfo"] as? String).map { String($0.prefix(4)) } }
        func name(_ m: [String: Any]) -> String { normalized(m["name"] as? String ?? "") }

        let pick = metas.first { name($0) == want && (year == nil || yearOf($0) == year) }
            ?? metas.first { year != nil && yearOf($0) == year && name($0).contains(want) }
        guard let m = pick, let id = m["id"] as? String, let n = m["name"] as? String else { return nil }
        return MetaItem(id: id, type: type, name: n, poster: m["poster"] as? String, background: nil, description: nil,
                        releaseInfo: m["releaseInfo"] as? String, runtime: nil, genres: m["genres"] as? [String], videos: nil)
    }
}

// MARK: - Importing

@MainActor
final class ImportRunner: ObservableObject {
    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var message: String?

    func run(url: URL, store: AddonStore, watched: WatchedStore) async {
        running = true; done = 0; total = 0; message = nil
        defer { running = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { message = "Couldn't read that file."; return }

        if url.pathExtension.lowercased() == "json" {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            guard let backup = try? dec.decode(BackupFile.self, from: data), backup.app == "NuviGo" else {
                message = "That isn't a NuviGo backup file."; return
            }
            let have = Set(store.savedURLs)
            let newURLs = backup.addons.filter { !have.contains($0) }
            if !newURLs.isEmpty {
                store.setURLs(store.savedURLs + newURLs)
                await store.load()
            }
            let added = watched.merge(backup.watched)
            message = "Added \(newURLs.count) add-ons and \(added) titles."
            return
        }

        if url.lastPathComponent.lowercased().contains("watchlist") {
            message = "That looks like a watchlist, not watched history. Import watched.csv or ratings.csv instead."
            return
        }
        let entries = DataPortability.parseCSV(String(decoding: data, as: UTF8.self)).compactMap(DataPortability.entry)
        guard !entries.isEmpty else {
            message = "No titles found. Use a Letterboxd, IMDb ratings or NuviGo CSV."; return
        }
        total = entries.count
        var found: [WatchedItem] = []
        var missed = 0
        var index = 0
        while index < entries.count {
            let chunk = Array(entries[index ..< min(index + 4, entries.count)])
            index += chunk.count
            let results = await withTaskGroup(of: WatchedItem?.self) { group in
                for e in chunk { group.addTask { await DataPortability.item(for: e) } }
                var out: [WatchedItem?] = []
                for await r in group { out.append(r) }
                return out
            }
            for r in results { if let r { found.append(r) } else { missed += 1 } }
            done = index
        }
        let added = watched.merge(found)
        message = "Added \(added) titles." + (missed > 0 ? " \(missed) couldn't be matched." : "")
    }
}

// MARK: - Account section

/// Back up, restore, and bring in history from Letterboxd or IMDb.
struct DataPortabilitySection: View {
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var watched: WatchedStore
    @StateObject private var runner = ImportRunner()
    @State private var picking = false
    @State private var backupURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        Section {
            if let backupURL {
                ShareLink(item: backupURL) { Label("Export backup", systemImage: "square.and.arrow.up") }
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("Export watched list (CSV)", systemImage: "tablecells") }
            }
            Button { picking = true } label: { Label("Import from a file", systemImage: "square.and.arrow.down") }
                .disabled(runner.running)
            if runner.running {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Matching titles… \(runner.done) of \(runner.total)").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let m = runner.message {
                Text(m).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Import a NuviGo backup, a Letterboxd watched.csv or ratings.csv, or an IMDb ratings export. Titles you already have are kept.")
        }
        .task(id: watched.items.count) { prepareFiles() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            Task { await runner.run(url: url, store: store, watched: watched) }
        }
    }

    private func prepareFiles() {
        let dir = FileManager.default.temporaryDirectory
        let b = dir.appendingPathComponent("NuviGo-backup.json")
        if let d = DataPortability.backupData(addons: store.savedURLs, watched: watched.items), (try? d.write(to: b)) != nil {
            backupURL = b
        }
        let c = dir.appendingPathComponent("NuviGo-watched.csv")
        if (try? DataPortability.csv(watched: watched.items).write(to: c)) != nil { csvURL = c }
    }
}
