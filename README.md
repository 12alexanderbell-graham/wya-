# wya?!

wya?! ("where you at?!") is a travel app for keeping track of where you've been and planning where you go next. You stamp the countries, regions and places you've visited on a map of the whole world, and the app keeps your passport, your lists and your streak.

It is being rebuilt from scratch as a native iOS app in SwiftUI, with a Metal map and Liquid Glass, for iOS 27.

## State of the build

The map is built: the world map with every border drawn the way the chosen point of view sees it (de facto, the UN's, or a country's own), the sheet that rises over it with the solar system at full height, search, the tools and settings, with place pages for every country, region and town. The passport, profile, lists and plans (a calendar of your days, an hour-by-hour day, calendar files in and out, your next trip on top) are being built now. The AI is reached through Siri: its answers, plans and suggestions come from the Claude API, with what it knows about your map, lists, plans and trip.

## Folders

| Folder | What |
|---|---|
| `app/` | The Xcode project (`wya?!.xcodeproj`) and the app's source (`wya/`): Swift, Metal shaders and the bundled map data. |
| `fonts/Tellus/` | Tellus, the app's display font: every letter traced from a real place seen from above. See its README. |
| `data/` | The scripts that build the map data, and the OpenStreetMap boundaries the de facto lines come from. See its README. |
| `server/` | The data server for the travel data (country facts, climate, places, region shapes and more) and its tests. |
| `tools/` | Scripts for checking the running app on the simulator frame by frame. |

## Building

Open `app/wya?!.xcodeproj` in Xcode (iOS 27 SDK) and run the `wya` target on an iPhone simulator. The map data is bundled, so the map works offline.

## Credits and licence

The data sources and their licences are in [CREDITS.md](CREDITS.md). The code, the font and the art are © 2026, all rights reserved: see [LICENSE](LICENSE).
