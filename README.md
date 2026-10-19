# JSON2Proto

Converts the JP, EN, TC, CN and KR Sekai master databases into binary Protobuf
lists. Each file contains all five regions (`tc` corresponds to SekaiKit's `tw`).

| Output | Sources |
| --- | --- |
| `gacha.proto` | `gachas.json` |
| `character.proto` | `characterProfiles.json`, `gameCharacters.json`, `gameCharacterUnits.json` |
| `event.proto` | `events.json`, `eventDeckBonuses.json`, `eventCards.json`, `eventMusics.json`, `eventStories.json`, JP `gameCharacterUnits.json` |
| `card.proto` | `cards.json` |
| `song.proto` | `musics`, `musicTags`, `musicDifficulties`, JP/EN `musicArtists`, `musicVocals`, `outsideCharacters`, `gameCharacters`, `releaseConditions`; shared `music_metas.json` |
| `fixture.proto` | `mysekaiFixtures`, both genre tables, `mysekaiBlueprints`, `mysekaiBlueprintMysekaiMaterialCosts`, `mysekaiMaterials` |
| `sticker.proto` | `stamps.json` |
| `comic.proto` | Comic records in `tips.json` |
| `skill.proto` | `skills.json`, including effects and level values |
| `release_condition.proto` | `releaseConditions.json` |
| `episode.proto` | `eventStories`, `unitStories`, `cardEpisodes`, `character2ds` |

Build with the JSON2Proto Xcode scheme, or use SwiftPM (Swift 6.2 or newer):

```sh
swift run JSON2Proto output/
swift test
```

For reproducible offline conversions, pass `--input-folder master-data/`. That
folder must contain `jp/`, `en/`, `tc/`, `cn/`, and `kr/`, each containing all of
the applicable source tables above, plus `shared/music_metas.json` at the input root. A failed download, invalid table, duplicate entity ID,
or missing character join fails conversion instead of publishing partial data.

The Update Assets workflow runs tests, builds, converts, and publishes only
the eleven corresponding `.aar` archives to
`Chorus-ACE/Sekai-Protobuf-Assets`. Each Apple Archive contains its corresponding
binary `.proto` file. The raw `.proto` outputs remain local build intermediates;
legacy raw binaries are removed from the destination on the next successful run.
The files in `SekaiProtoDef/` are schema definitions.

The workflow checks every hour, on pushes, and on manual runs. Before building,
it compares the Git blob SHAs of all required regional source JSON files (including `musicArtists` only for JP/EN)
against the last successful run stored in GitHub Actions cache. The external song statistics source is checked by SHA-256; its exact checked bytes are included in the snapshot so conversion cannot race a later external update. Unrelated upstream
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
Event introductions (`outline`) are joined from each region’s `eventStories.json`
by `eventId`; missing and empty introductions remain distinct. Old archives decode
with no introduction. Regenerate and publish `event.aar` to deliver this field.
Event card/music IDs are included for ExtendedEvent. Optional fields preserve
presence, timestamps use milliseconds, and string enums retain upstream values.
`JSON2Proto/EarlyEventUnits.swift` explicitly corrects the unit of events #1–42
in every region, including `none` for mixed-unit events. This compiled data table
repairs historical upstream `none` values without requiring runtime resource files.
Events #43 onward retain their upstream unit. Regenerate and publish `event.aar`
for these corrections to reach clients.
The generator also joins JP story banner character-unit IDs to base character IDs
and computes `focus_character_id` and the one-based `focus_character_index`.
Counts use JP `startAt` order (event ID breaks ties), after historical unit
corrections, and exclude mixed-unit and World Link events. The resulting metadata
is shared by event ID across all regions, regardless of regional release order or
progress. Incomplete or inconsistent focus data for a unit event fails conversion
instead of silently shifting later counts. These fields are optional: old archives,
mixed events, World Link, and events absent from JP history have no focus metadata.
Card parameters accept both the expanded JP/EN records and the compact TC/CN/KR
arrays, preserving the power at each level in the same wire format.

## Updating the schema

`SekaiProtoDef/` is the source of truth. Never renumber or reuse existing fields.
After editing any schema, run:

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

## Joined content and migration

`Content.proto` defines typed records; no JSON strings or opaque JSON payloads are stored in the archives.
Songs include regional credits, chart levels/counts, tags, media, vocalists and resolved unlock conditions.
The song archive also carries the complete external vocalist list and shared chart statistics.
Fixtures include genre names and all blueprints with their material costs. A missing material master
record preserves the referenced ID and quantity with no name; an absent blueprint is distinct from a
blueprint with zero materials. Episode records include parent ID, kind, titles and regional asset paths;
character mappings share their archive. Scenario bodies remain JSON and are loaded on demand by SekaiKit.
Skills preserve fractional effect durations. Gacha additions retain unknown raw categories, optional
limits and full double-precision rates while preserving existing field numbers and legacy enums.
Rate rows without a source ID remain present; the client assigns a negative one-based index as their
display identity. Fractional skill durations and composer/arranger/lyricist credits are preserved.

External statistics currently use `https://storage.sekai.best/sekai-best-assets/music_metas.json`.
If that host returns 403 or fails, the scheduled run fails without publishing partial assets or advancing
its success state. Offline conversion accepts an explicitly supplied `shared/music_metas.json`; it never
silently substitutes empty or fabricated statistics. Verification samples must not be published.

The client requires these new archives before release. Updating source code alone does not publish them.
For conversion-to-client parity checks, set both `SEKAI_ADDITIONAL_PROTOBUF_ASSETS` to the archive directory
and `SEKAI_PROTOBUF_MASTER_DATA` to the offline input directory when running SekaiKit tests.
