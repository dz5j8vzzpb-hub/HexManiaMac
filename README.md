# HexManiaMac

**Pokémon ROM Editing, Made for Mac.**

HexManiaMac is a free and open-source graphical editor for Pokémon games on macOS. Its goal is to make Pokémon ROM hacking more approachable for Mac users, including people who do not have programming experience and do not want to rely on Windows.

The current editing toolset focuses on supported Pokémon Emerald ROMs. Everything needed to inspect and edit a ROM is presented through a native macOS interface, while a built-in hex editor remains available for lower-level work.

## Features

### Pokémon Emerald ROM editing

- Edit Pokémon species data, moves, trainers and trainer parties, items, and wild encounters.
- Browse and edit maps, including map blocks, object events, and warp events.
- Render Pokémon, trainer, object-event, map, and metatile graphics directly from the loaded ROM.
- Inspect map event scripts and navigate between map events and linked trainers.
- Compare supported data against an optional clean-ROM reference and filter modified entries.
- Apply or revert the compatibility-checked instant-dialogue patch on supported Emerald ROMs.

### Save editing

- Open Pokémon Emerald `.sav` files.
- Edit party Pokémon, bag contents, and Pokédex seen/caught state.
- Inspect save metadata, PC boxes, trainer information, story progression, and advanced save structures.
- Link a legally obtained Emerald ROM as a local, read-only graphics source for save-file sprites.
- Create a backup before overwriting a save file.

### Hex editing and file safety

- Browse ROM data in a paged, 16-byte-wide hex view.
- Edit individual bytes and use undo and redo.
- Search for hexadecimal byte sequences or UTF-8 text.
- Jump directly to a hexadecimal or decimal ROM offset.
- Save in place or use Save As.
- Write files atomically, verify saved ROM data, and create a timestamped backup before overwriting a ROM.

### Team Coach

- Build and analyze a six-Pokémon team using data read from a supported Emerald ROM.
- Import party, Pokédex, and progression information from an Emerald save.
- Review type coverage and locally generated team recommendations.
- Use the tool in read-only mode: Team Coach does not modify the loaded ROM or save.

### Interface

- Native SwiftUI interface for macOS.
- English and Italian application languages.
- Keyboard shortcuts for opening, saving, closing, undoing, and redoing.

## Supported Games

Full structured editing is currently limited to these Game Boy Advance ROM revisions:

| Game | Region / language | Game code | Support |
| --- | --- | --- | --- |
| Pokémon Emerald | USA / English | `BPEE` | Supported |
| Pokémon Emerald | Italy / Italian | `BPEI` | Supported |

HexManiaMac opens ROMs through the `.gba` file type. A generic GBA ROM can be viewed in the hex workspace, but the structured Pokémon editors require one of the supported Emerald game codes above. Modified ROM layouts may be rejected by individual parsers or editing operations when expected tables and bytes cannot be validated.

Pokémon Ruby, Sapphire, FireRed, and LeafGreen USA headers are recognized for identification only; their structured editors are not implemented. Pokémon Sword and Shield dump detection is experimental: the app can validate an extracted `RomFS`/`ExeFS` directory and identify the game, but all Sword and Shield editing sections are currently unavailable. Text editing is also not yet implemented.

## Requirements

### Running HexManiaMac

- macOS 13 Ventura or later.
- A Mac with Apple Silicon or an Intel processor. The target build settings include both `arm64` and `x86_64`; Intel runtime behavior has not yet been independently verified for this README.
- A legally obtained ROM or save file for a supported game. ROMs and commercial game data are not included.

### Building HexManiaMac

- Xcode capable of targeting macOS 13 and compiling Swift 5 source.
- The repository contents; no third-party package manager or external build dependency is required.

The project records Xcode 16.0 creation metadata, but it does not declare a formal minimum Xcode version. The exact oldest compatible Xcode release has not been verified.

## Getting Started

### Using a future official release

No official release download is linked yet. When releases become available, download the macOS application from the project's GitHub Releases page, move it to your Applications folder if desired, and open it normally.

You must create or obtain your own ROM dump legally. HexManiaMac does not provide, download, or distribute commercial ROMs.

### Opening and editing a ROM

1. Launch HexManiaMac and select Pokémon Emerald.
2. Choose **Open ROM**, then select a supported `.gba` file.
3. Select an editor from the sidebar and make the desired changes.
4. Use **File > Save** to overwrite the opened ROM, or **File > Save As** to write a separate copy.

Keep an additional backup of important ROMs and saves. HexManiaMac creates backups for overwrite operations, but independent backups are still recommended.

### Opening a save

1. Select Pokémon Emerald on the home screen.
2. Choose **Open Save**, then select an Emerald `.sav` file.
3. Use the save workspace to inspect or edit supported data.
4. Use **File > Save** to write validated changes back to the save file.

## Building from Source

1. Download or clone the project source when the GitHub repository becomes available.
2. Open `HexManiaMac.xcodeproj` in Xcode.
3. Select the `HexManiaMac` scheme.
4. Choose **My Mac** as the run destination.
5. Build and run with **Product > Run** or `Command-R`.

The project uses the generic bundle identifier `org.example.hexmaniamac`. Developers preparing a signed distribution should replace it with a bundle identifier they control and configure their own signing settings. No Apple Developer Team ID or provisioning profile is stored in the project.

## Contributing

Contributions are welcome once the GitHub repository is available.

- Use GitHub Issues to report reproducible bugs, including the game code and the operation that failed. Do not upload or attach copyrighted ROMs or save files containing personal data.
- Use an issue or discussion to propose a feature before starting a large change.
- Submit focused Pull Requests that explain the behavior being changed and how it was tested.
- Preserve compatibility checks, file backups, third-party notices, and the rule that ROM files must never be committed.

## Privacy

HexManiaMac is designed to perform ROM and save processing locally on the Mac. The current source code contains no network client, analytics, advertising, account system, or telemetry integration.

The app reads files explicitly selected by the user, writes only during requested save operations, stores interface preferences locally, and may store a security-scoped bookmark for a linked reference ROM. Debug builds can print selected file paths and editing diagnostics to the local Xcode console.

## Legal Disclaimer

HexManiaMac is an independent, unofficial project. It is not affiliated with, endorsed by, approved by, or sponsored by Nintendo, Game Freak, Creatures Inc., or The Pokémon Company.

Pokémon and all related names, characters, trademarks, and game assets are the property of their respective owners. HexManiaMac does not include or distribute commercial ROMs, save files, BIOS files, or other copyrighted game data. Users are responsible for complying with the laws that apply to their own backups and modifications.

## License and Credits

HexManiaMac is free and open-source software distributed under the MIT License. See [LICENSE](LICENSE) for the license covering HexManiaMac's original code.

HexManiaMac is inspired by the workflow and architecture of Hex Maniac Advance. Hex Maniac Advance is Copyright (c) 2018 haven1433 and is distributed under the MIT License. Its attribution and license notice are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The HexManiaMac license does not replace or remove copyright notices and license terms that apply to third-party material.
