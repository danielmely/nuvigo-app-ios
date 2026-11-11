# Setting up the new features in Xcode

All of this Swift is uncompiled. Fix any compile errors first, then do the setup below.

## 1. New files
Add to the **NuviGo app target**: SharedSnapshot, DownloadActivity, WidgetBridge, DeepLink, EpisodeAlerts,
SpotlightIndexer, NuviGoIntents, DownloadLiveActivity, WatchTogether, StatsStore.
Replace: NuviGoApp, PlayerView, BrowseView, SearchView, Components, ProgressStore, Privacy, AccountView.

## 2. Widget extension (widgets + download Live Activity)
1. File > New > Target > **Widget Extension**. Name it `NuviGoWidgets`. Tick **Include Live Activity**, untick Include Configuration App Intent.
2. Delete the files Xcode generated. Add `Widgets/NuviGoWidgets.swift` to that target.
3. Select `SharedSnapshot.swift` and `DownloadActivity.swift` and tick **both** targets in the File inspector.
4. Both targets: Signing & Capabilities > **+ Capability > App Groups** > add `group.com.nuvigo.app`
   (or change `NuviGoShared.appGroup` in SharedSnapshot.swift to your own).
5. App target Info.plist: `NSSupportsLiveActivities` = YES, and a URL type with scheme `nuvigo`.

## 3. Other capabilities and plist entries (app target)
- **Group Activities** capability (SharePlay).
- Push notifications are NOT needed. Episode alerts are local.
- Siri and Spotlight need nothing extra. Shortcuts appear in the Shortcuts app after the first launch.

## 4. iPad
Target > General > Supported Destinations: add **iPad**. The dashboard shows four columns on wide screens.

## 5. Test checklist
- Long-press the Home Screen > add the Continue Watching and Coming Up widgets (play something first, then background the app).
- Account > Notifications > New episode alerts (needs Trakt connected).
- Search the iPhone for a title you've watched.
- Say "Continue watching in NuviGo".
- Start a download and lock the phone to see the Live Activity.
- FaceTime a friend, open the player, tap the SharePlay button.
- Account > Your stats after watching a few minutes.

---

# Round 2: gestures, subtitle style, trailers, icons, languages

## App icons (Info.plist)
1. Drag the `AlternateIcons` folder into the app target ("Copy items if needed", tick the app target, folder reference or group both work as long as the PNGs end up in the app bundle).
2. Info.plist, add this (Xcode's Info tab: "Icon files (iOS 5)" > "Alternate Icons"), or paste in the source:
```xml
<key>CFBundleIcons</key>
<dict>
  <key>CFBundleAlternateIcons</key>
  <dict>
    <key>IconMidnight</key><dict><key>CFBundleIconFiles</key><array><string>IconMidnight</string></array></dict>
    <key>IconMono</key><dict><key>CFBundleIconFiles</key><array><string>IconMono</string></array></dict>
    <key>IconSunrise</key><dict><key>CFBundleIconFiles</key><array><string>IconSunrise</string></array></dict>
    <key>IconOcean</key><dict><key>CFBundleIconFiles</key><array><string>IconOcean</string></array></dict>
  </dict>
</dict>
```
If your Info.plist already has `CFBundleIcons`, add `CFBundleAlternateIcons` inside it.
"Default" is your normal AppIcon. Account > App icon shows the picker.

## Languages (Spanish, French, Japanese, Chinese)
1. Add `Localizable.xcstrings` to the app target. Also tick the widget extension target (it has a few strings).
2. Project > Info > Localizations > **+** Spanish, French, Japanese, Chinese (Simplified), in that order.
3. Build once. Xcode adds any new strings it finds to the catalog. Test: Settings > NuviGo > Language, or run the scheme with App Language set.
- Covered: tabs, dashboard cards, Account settings, player menus, Search, Stats, profiles and PIN, alerts, most buttons and messages (about 240 strings).
- Not translated yet: the Add-on Disclosures and Terms/Privacy text, the long help text, the startup loading jokes, and any message that has a number or name inside it (for example "3 in progress").
- The translations are my own. Please have a native speaker of each language skim them before release, especially Japanese and Chinese.

## Other new settings
Account > Playback: Spoiler guard, Player gestures. Account > Downloads: Delete after I finish watching. Account > Subtitle style. Trailers use TMDB, so the TMDB key must be set.
