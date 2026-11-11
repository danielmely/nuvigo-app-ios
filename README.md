# NuviGo (starter)

SwiftUI iOS 17+ app that installs Stremio-protocol addons by URL, browses their catalogs, and plays direct-URL streams.

## Setup
1. Xcode → New Project → iOS App → SwiftUI. Name it NuviGo.
2. Delete the generated `App` and `ContentView` files (and `HomeView.swift` if you added it earlier; it's replaced by the Browse, Category, Search and Components files), then drag all `.swift` files in this folder into the project.
3. Set the iOS deployment target to 17.0 (uses `ContentUnavailableView` and the new `onChange`).
4. **Trakt:** create an app at trakt.tv/oauth/applications (redirect URI `urn:ietf:wg:oauth:2.0:oob`), then paste its Client ID and Secret into `TraktConfig` in `TraktClient.swift`.
5. **Other services (all optional):** open `Config.swift` and paste in whichever keys you want. Each line says where to get one. Anything left as `YOUR_…` just shows a hint in the Account tab.
   - AniList: redirect URL `nuvigo://anilist`. MyAnimeList: app type "other", redirect URL `nuvigo://mal`. Simkl, OpenSubtitles and TMDB need no redirect.
   - Jellyfin, Plex, Real-Debrid, TorBox, AllDebrid and Premiumize need no keys: you sign in with your own account in the app.
   - **Local servers:** add `NSLocalNetworkUsageDescription` to Info.plist (any text, e.g. "Connects to your media server"), and for plain `http://` servers set `NSAllowsLocalNetworking = YES` under `NSAppTransportSecurity`.
5b. **mkv and other formats (optional):** Xcode → File → Add Package Dependencies → `https://github.com/kingslay/KSPlayer` → Dependency Rule: Branch, `main` → add the `KSPlayer` library to the app target (it's a big download because it bundles FFmpeg). Once it's added, `AltPlayer.swift` switches on by itself and mkv, avi, webm and similar files open in KSPlayer. Its API changes between versions, so if `KSVideoPlayerView(url:options:)` doesn't compile, adjust that one line in `AltPlayer.swift`. Without the package those files show an "unsupported format" message and are ranked last.
5c. **iCloud:** target → Signing & Capabilities → + Capability → iCloud → check **Key-value storage**. Sign into iCloud on each device/simulator. Without this the app still works, it just doesn't sync.
6. **Background Modes** (for Picture in Picture and audio): target → Signing & Capabilities → + Capability → Background Modes → check **Audio, AirPlay, and Picture in Picture**.
7. Run. Go to the Addons tab, paste an addon URL (https://…/manifest.json or stremio://…), tap Install.

## What's here
- `Models.swift` – manifest / catalog / meta / stream types (handles string-or-object `resources`)
- `AddonClient.swift` – fetches manifest, catalog (+search), meta, streams
- `AddonStore.swift` – saved addon URLs, mirrored to iCloud so they sync across devices; re-fetches manifests on launch
- `BrowseView.swift` – Dashboard tab: category cards (Continue watching, Watchlist, Movies, Series, genres)
- `CategoryView.swift` – what opens when you tap a category card
- `SearchView.swift` – Search tab, searches as you type; empty state shows streaming-service and genre cards
- `NuviAccount.swift`, `NuviAccountViews.swift` – NuviGo accounts: sign-up, sign-in and sync of addons, progress, settings and logins (server code is in the nuvigo-server repo)
- `WatchedStore.swift`, `WatchedViews.swift` – the Already watched card: everything you have watched, your 1-10 ratings, and three picks with a "likely to like" score
- `Ratings.swift` – IMDb and Rotten Tomatoes ratings on the movie page (needs a free OMDb key in Config.swift)
- `StreamingServices.swift` – service and genre card models, plus the screen they open (needs a TMDB key for services)
- `Components.swift` – shared poster row, poster and continue cards, watchlist loader
- `DetailView.swift` – details, episode picker, stream list from every addon that supports it
- `PlayerView.swift` – full-screen player: resume, subtitles menu, AirPlay, Picture in Picture, next-episode countdown
- `ProgressStore.swift` – playback positions and the Continue watching row
- `Subtitles.swift` – SRT/WebVTT parser and loader (subtitles come from addons)
- `CoverArt.swift` – loads the poster art shown on the Dashboard cards (from your addons, Trakt lists and libraries)
- `Theme.swift` – the accent color (purple) and the System/Light/Dark appearance setting; `StreamBadges.swift` – the icon row under each stream (resolution, HDR, codec, file type, source)
- `LaunchView.swift` – the start-up screen (with `LogoData.swift`, your embedded logo), and the preloader that caches addons, catalogs and covers while its loading bar fills
- `StreamRanker.swift` – reads quality from stream names (4K / 1080p / HDR / codec) and sorts the best playable stream first
- `AltPlayer.swift`, `PlayerSurface.swift` – the extra mkv player hook, and the real AVPlayerViewController (Picture in Picture hands back to the full-screen player)
- `Downloads.swift` – offline downloads: background file downloads, HLS downloads, the Downloads screen rows
- `ResponseCache.swift` – saves addon responses to disk for offline use, plus the online/offline monitor
- `Debrid.swift` – Real-Debrid, TorBox, AllDebrid and Premiumize clients for torrent streams, plus `FeatureFlags.debridEnabled`
- `Keychain.swift` – small Keychain helper for tokens
- `AddonsView.swift` – install / remove addons
- `TraktClient.swift` – Trakt device-code login (token kept in Keychain), token refresh, scrobbling
- `AccountView.swift`, `AccountSections.swift` – Account tab: one section per service
- `Config.swift` – keys for Simkl, AniList, MyAnimeList, OpenSubtitles, TMDB
- `Services.swift` – holds every optional service in one place; records finished titles on Simkl / AniList / MAL
- `Simkl.swift`, `AnimeTrackers.swift` – Simkl (PIN), AniList and MyAnimeList (browser sign-in)
- `Libraries.swift` – Jellyfin and Plex as your own media libraries (cards on Dashboard, results in Search)
- `OpenSubtitles.swift`, `TMDB.swift` – extra subtitles; posters, descriptions and ratings
- `HTTP.swift`, `WebAuth.swift` – shared networking and browser sign-in helpers

## Known limits / next steps
- **Trakt secret** ships inside the app (device-code login requires it). Fine for a personal/indie app; it can only be used with your Trakt app's limits.
- **Scrobbling** covers IMDb-style ids (`tt…`), which most addons use. Trakt marks an item watched when playback stops at 80% or more.
- **iCloud sync** is last-write-wins on the addon list.
- **Torrent streams** play only when a debrid account (Real-Debrid, TorBox, AllDebrid or Premiumize) is connected, and only if the torrent is already cached there (otherwise you get a "not cached" message). With several connected, each is tried in turn. Set `FeatureFlags.debridEnabled = false` for an App Store build if you'd rather not ship it.
- **Subtitles** are drawn by the app (AVPlayer can't load external files). Embedded tracks inside a stream still appear in the player's own subtitle menu.
- **Picture in Picture** works from the player's controls once the Background Modes capability is on; tapping the PiP window returns to the full-screen player.
- **Next episode** picks a stream from the same source as the one you chose when it can, and counts down 6 seconds before starting.
- **AVPlayer** only plays mp4/m4v/HLS; add the KSPlayer package (step 5b) for mkv and wider codecs.
- **App Transport Security:** many streams are plain http. Adding `NSAllowsArbitraryLoadsForMedia = YES` under `NSAppTransportSecurity` in Info.plist covers media loads without opening everything; App Review may ask why.
- **App Review:** ship with no default addons; keep addon entry entirely user-supplied.
- **Jellyfin / Plex** play through a server-side transcode (HLS, H.264/AAC), so mkv and other formats work but the server does the converting. Subtitles from the server itself aren't loaded. Library items don't scrobble to Trakt (they have no IMDb id).
- **AniList / MyAnimeList** look shows up by title, only for anime (an "Anime" genre or a Kitsu/MAL/AniList/AniDB id), and update progress when you watch 80% or more. A title with an unusual name can match the wrong entry.
- **Simkl** history uses IMDb ids, like Trakt.
- **OpenSubtitles** free accounts have a daily download limit. Tracks are fetched when you pick them, so the menu fills instantly.
- **TMDB** only fills in what an addon left blank; it never overwrites addon data.
- **IMDb and Letterboxd** are not included: neither offers a usable public login for apps.
- **Untested:** none of this has been compiled or run against the real services yet, so expect a few small fixes the first time you build in Xcode.
- **Playback screen:** audio and subtitle menus include tracks inside the file; speed menu (also on the native controls); "Skip intro" appears in the first 6 minutes of episodes and jumps by the length set in Account → Playback (not detected automatically: no free source has intro timestamps for every show); "Next episode" appears in the last 90 seconds.
- **KSPlayer path** has its own controls, so on those files there's no resume position, scrobbling, Up Next card or tracker updates.
- **Stream ranking** reads the names addons give; a stream with no quality in its name is treated as low. Torrent streams can't be checked for cached status until you tap them.
- **Dashboard:** home rows show the first four browsable catalogs of your addons. "Coming up" uses your Trakt calendar (shows you follow). Long-press a poster to mark watched, or to add it to your watchlist; long-press a Continue watching card to remove it.
- **Offline:** catalogs, details and addon manifests you've opened are saved for 30 days, and posters are cached. Playback and searches need a connection.
- **Downloads:** tap the download button next to any stream (it resolves debrid links first). Plain files use a background download and keep going with the app closed; HLS streams (Jellyfin / Plex transcodes) use Apple's HLS downloader, which is slower and more fragile with transcoders: treat it as best effort. Downloaded copies play with no connection, appear under Dashboard → Downloads, and are preferred for the next episode. They aren't backed up to iCloud. Debrid links can expire, so a download must start right after you tap it. mkv downloads need the KSPlayer package to play. Watch-history updates (Trakt and the others) are skipped while you're offline.

## First-time setup
`Config.swift` holds API keys and is not in git. Copy `Config.example.swift` to `Config.swift`, add it to the Xcode target, and fill in your keys. See `SETUP-NEW-FEATURES.md` for the widget, App Group and other capability setup.
