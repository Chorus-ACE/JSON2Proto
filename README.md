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

The Update Assets workflow runs tests, builds, converts, and publishes only
`gacha.aar`, `character.aar`, `event.aar`, and `card.aar` to
`Chorus-ACE/Sekai-Protobuf-Assets`. Each Apple Archive contains its corresponding
binary `.proto` file. The raw `.proto` outputs remain local build intermediates;
legacy raw binaries are removed from the destination on the next successful run.
The files in `SekaiProtoDef/` are schema definitions.

The workflow checks every hour, on pushes, and on manual runs. Before building,
it compares the Git blob SHAs of the 45 source JSON files (9 tables × 5 regions)
against the last successful run stored in GitHub Actions cache. Unrelated upstream
commits are ignored. A changed converter repository revision, missing cache, or
missing/changed published files also triggers conversion. Manual runs have a
`force` option to bypass this check.

Downloads use the checked commit for each region and verify every Git blob SHA.
After conversion, only changed Protobuf contents are recompressed; unchanged
archives are retained so archive timestamps do not create false changes. Cached
content hashes are bound to archive hashes; when the cache is missing, existing
archives are extracted locally for comparison. Commits
and normal pushes happen only when published assets change. Runs are serialized.
The existing asset history is preserved.

Successful source checks are cached even when new JSON produces identical Protobuf,
so the next hourly run can skip conversion. Failed downloads, builds, conversions,
or pushes never advance the successful state. If the Actions cache expires, the
workflow converts once again and still avoids publishing identical output.

Run the update-check regression tests with:

```sh
python3 -m unittest discover -s Scripts/tests -v
```

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
mkdir -p archives
python3 Scripts/update_assets.py prepare --generated output --published archives
SEKAI_PROTOBUF_TEST_ASSETS="$PWD/archives" swift test --package-path ../SekaiKit
```

Note: This lovely README.md is purely vibe-coded.
