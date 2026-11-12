import Foundation
import Combine

// MARK: - Manifest

nonisolated struct AddonManifest: Decodable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let types: [String]?
    let idPrefixes: [String]?
    let resources: [ResourceDecl]
    let catalogs: [CatalogDecl]

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, version, description, logo, types, idPrefixes, resources, catalogs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        types = try c.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try c.decodeIfPresent([String].self, forKey: .idPrefixes)
        resources = (try? c.decode([ResourceDecl].self, forKey: .resources)) ?? []
        catalogs = (try? c.decode([CatalogDecl].self, forKey: .catalogs)) ?? []
    }
}

/// A resource can be a plain string ("stream") or an object with its own types/prefixes.
nonisolated struct ResourceDecl: Decodable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?

    nonisolated private struct Obj: Decodable {
        let name: String
        let types: [String]?
        let idPrefixes: [String]?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            name = s; types = nil; idPrefixes = nil
        } else {
            let o = try c.decode(Obj.self)
            name = o.name; types = o.types; idPrefixes = o.idPrefixes
        }
    }
}

nonisolated struct CatalogDecl: Decodable, Identifiable {
    let type: String
    let id: String
    let name: String?
    let extra: [ExtraDecl]?

    var uid: String { "\(type)/\(id)" }
    var displayName: String { name ?? id.capitalized }

    /// Can be browsed with no extra input (no required filters like genre/search).
    var isBrowsable: Bool {
        !(extra ?? []).contains { $0.isRequired == true }
    }
    var supportsSearch: Bool {
        (extra ?? []).contains { $0.name == "search" }
    }
    var genreOptions: [String] {
        (extra ?? []).first { $0.name == "genre" }?.options ?? []
    }
    func supportsGenre(_ genre: String) -> Bool { genreOptions.contains(genre) }
}

nonisolated struct ExtraDecl: Decodable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
}

// MARK: - Content

nonisolated struct MetaItem: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let runtime: String?
    let genres: [String]?
    let videos: [Video]?

    static func == (l: MetaItem, r: MetaItem) -> Bool { l.id == r.id && l.type == r.type }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(type) }
}

nonisolated struct Video: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let name: String?
    let season: Int?
    let episode: Int?
    let thumbnail: String?

    var label: String { title ?? name ?? id }

    /// "S1E2", with no title (used by the spoiler guard).
    var episodeNumberOnly: String {
        (season != nil && episode != nil) ? "S\(season!)E\(episode!)" : "Episode"
    }

    /// "S1E2 · Title"
    var episodeTitle: String {
        let prefix = (season != nil && episode != nil) ? "S\(season!)E\(episode!) · " : ""
        return prefix + label
    }
}

nonisolated struct Stream: Decodable, Identifiable {
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let name: String?
    let title: String?
    let description: String?
    let externalUrl: String?

    var id: String { url ?? infoHash ?? externalUrl ?? UUID().uuidString }
    /// Direct URLs play natively. Torrent hashes need a debrid service (see Debrid.swift).
    var hasDirectURL: Bool { url != nil }
    var displayTitle: String { [name, title ?? description].compactMap { $0 }.joined(separator: "\n") }
}

// MARK: - Response wrappers

nonisolated struct CatalogResponse: Decodable { let metas: [MetaItem] }
nonisolated struct MetaResponse: Decodable { let meta: MetaItem }
nonisolated struct StreamResponse: Decodable { let streams: [Stream] }

// MARK: - Subtitles

nonisolated struct SubtitleTrack: Decodable, Hashable {
    let url: String             // empty for OpenSubtitles tracks until they're resolved with `fileID`
    let lang: String?
    var fileID: Int? = nil      // OpenSubtitles file id

    var languageName: String {
        let code = lang ?? "und"
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}

nonisolated struct SubtitleResponse: Decodable { let subtitles: [SubtitleTrack] }

// MARK: - Playback

/// Everything the player needs to know about what is playing.
nonisolated struct PlaybackContext {
    let key: String             // stream id: movie id, or episode id like "tt123:1:2"
    let item: MetaItem          // the parent title
    let episodeLabel: String?   // "S1E2 · Title"
    let nextEpisode: Video?     // nil for movies and last episodes
}

// MARK: - Language preferences

/// Normalises the 2- and 3-letter language codes that addons and video files use, so "eng" and "en" match.
nonisolated enum LanguagePref {
    static let choices: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ru", "Russian"),
        ("ar", "Arabic"), ("hi", "Hindi")
    ]
    private static let three: [String: String] = [
        "eng": "en", "spa": "es", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it", "por": "pt",
        "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "rus": "ru", "ara": "ar", "hin": "hi"
    ]

    static func code(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? raw.lowercased()
        return three[lower] ?? lower
    }
}
