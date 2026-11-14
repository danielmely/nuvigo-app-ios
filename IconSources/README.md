# App icon sources (1024 x 1024)

- AppIcon-1024.png: the main icon (white mark on a purple gradient).
- AppIcon-Dark-1024.png: iOS 18 dark appearance for the main icon.
- AppIcon-Tinted-1024.png: iOS 18 tinted appearance for the main icon.
- IconMidnight / IconMono / IconOcean / IconSunrise: the four alternate icons.

Xcode: Assets.xcassets > AppIcon > Any / Dark / Tinted slots get the first three files.
Each alternate becomes its own App Icon set with the exact name shown (IconMidnight, IconMono, IconOcean, IconSunrise),
then Build Settings > "Alternate App Icon Sets" lists all four names separated by spaces.
