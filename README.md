# TwoTabs Notch

**TwoTabs Notch** by **TwoTabs Studio** turns the MacBook notch into a small control center: music controls with a live visualizer, calendar and reminders, a mirror, system HUD replacements, and a file shelf with AirDrop.

On top of that, this fork adds the TwoTabs features:

- **Smart shelf** - the shelf suggests actions for what you drop on it.
- **Claude Code pet** - a small animated pet in the notch that reacts to what Claude Code is doing.
- **Screenshot catcher** - new screenshots land on the shelf automatically.
- **Clear-all shortcut** - empty the shelf with a single keyboard shortcut.

## Build

Requires macOS 15.6 or later and Xcode 26 or later.

```bash
git clone https://github.com/okashiina/boring.notch.git
cd boring.notch
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath build/DerivedData -scmProvider system -skipPackageUpdates CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

The built app is in `build/DerivedData/Build/Products/Debug/`. You can also open `boringNotch.xcodeproj` in Xcode and press Run.

The app is not notarized, so macOS may warn about an unidentified developer on first launch.

## Credits

TwoTabs Notch is a fork and stays free software under the **GPL-3.0** license (see [LICENSE](LICENSE)).

- Based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam (GPL-3.0). Most of the app, including the notch, music, calendar, HUD and shelf, comes from their work.
- The Claude Code pet sprites and logic are from [Notchi](https://github.com/sk-ruban/notchi) by sk-ruban (GPL-3.0). See `boringNotch/TwoTabs/ClaudePet/NOTICE.md`.
- Other open-source components, including MediaRemoteAdapter, NotchDrop and DynamicNotchKit, are listed with their licenses in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
