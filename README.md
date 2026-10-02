# JSON2Proto

Converts the JP, EN, TC, CN and KR Sekai master databases into binary Protobuf
lists. Each file contains all five regions (`tc` corresponds to SekaiKit's `tw`).

| Output | Sources |
| --- | --- |
| `gacha.proto` | `gachas.json` |
| `character.proto` | `characterProfiles.json`, `gameCharacters.json`, `gameCharacterUnits.json` |
| `event.proto` | `events.json`, `eventDeckBonuses.json`, `eventCards.json`, `eventMusics.json` |
| `card.proto` | `cards.json` |

Build with the JSON2Proto Xcode scheme, or use SwiftPM (Swift 6.2 or newer):

```sh
swift run JSON2Proto output/
swift test
```

For reproducible offline conversions, pass `--input-folder master-data/`. That
folder must contain `jp/`, `en/`, `tc/`, `cn/`, and `kr/`, each containing all of
the source tables above. A failed download, invalid table, duplicate entity ID,
or missing character join fails conversion instead of publishing partial data.

The Update Assets workflow runs tests, builds, converts, and publishes all four
binary `.proto` files alongside `.aar` archives to
`Chorus-ACE/Sekai-Protobuf-Assets`. The output `.proto` files are binary data;
the files in `SekaiProtoDef/` are schema definitions.

Character profiles and colors are joined by character ID. Event bonuses are
consolidated with virtual singer variants mapped to their base characters.
Event card/music IDs are included for ExtendedEvent. Optional fields preserve
presence, timestamps use milliseconds, and string enums retain upstream values.
Card parameters accept both the expanded JP/EN records and the compact TC/CN/KR
arrays, preserving the power at each level in the same wire format.

## Updating the schema

`SekaiProtoDef/` is the source of truth. Never renumber or reuse existing fields.
After editing Character, Event or Card schemas, run:

```sh
sh Scripts/sync-protos.sh
# Or pass an explicit SekaiKit/SekaiKit/Protobuf directory.
```

Both projects use SwiftProtobufPlugin to generate Swift types during the build.
Publish the updated assets before releasing a SekaiKit version that reads them.
To test a conversion through SekaiKit:

```sh
SEKAI_PROTOBUF_TEST_ASSETS="$PWD/output" swift test --package-path ../SekaiKit
```

Note: This lovely README.md is purely vibe-coded.
