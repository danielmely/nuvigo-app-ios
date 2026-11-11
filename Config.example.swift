import Foundation

/// IDs for the services NuviGo can sign in to. TMDB, OMDb and OpenSubtitles keys are not here: each person adds their own in Account. Trakt's live in TraktClient.swift.
/// Each one is free to register; the comment says where, and what redirect URI to use.
enum Config {
    /// https://simkl.com/settings/developer/
    static let simklClientID = "YOUR_SIMKL_CLIENT_ID"
    /// https://anilist.co/settings/developer  (redirect URL: nuvigo://anilist)
    static let anilistClientID = "YOUR_ANILIST_CLIENT_ID"
    /// https://myanimelist.net/apiconfig  (app type: other, redirect URL: nuvigo://mal)
    static let malClientID = "YOUR_MAL_CLIENT_ID"
    /// Your NuviGo server on Railway, with no trailing slash, e.g. "https://nuvigo-server-production.up.railway.app".
    /// It runs the accounts (sign-up, sign-in and sync).
    static let serverURL = "YOUR_SERVER_URL"

    /// Used by AniList and MyAnimeList sign-in.
    static let callbackScheme = "nuvigo"

    static func isSet(_ value: String) -> Bool { !value.hasPrefix("YOUR_") }
}

/// A stable random ID for this install, sent to Plex and Jellyfin to identify the app.
enum DeviceID {
    static var value: String {
        let key = "nuvigo.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
