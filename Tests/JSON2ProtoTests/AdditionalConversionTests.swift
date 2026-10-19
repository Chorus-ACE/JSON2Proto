import Foundation
import XCTest
import SwiftProtobuf
import SwiftyJSON
@testable import JSON2Proto

final class AdditionalConversionTests: XCTestCase {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testSongJoinsByIDAndNormalizesRegionalFormats() throws {
        let songs = try convertSongArray(
            musics: data(#"[{"id":3,"infos":[{"title":"Song","creator":"Creator","composer":"Composer","lyricist":"Lyricist","arranger":"Arranger"}],"categories":[{"musicCategoryName":"mv"}],"publishedAt":0,"releaseConditionId":4}]"#),
            tags: data(#"[{"musicId":3,"musicTag":"future_category"}]"#),
            charts: data(#"[{"musicId":3,"musicDifficulty":"master","playLevel":30,"totalNoteCount":100}]"#), artists: data("[]"),
            vocals: data(#"[{"id":9,"musicId":3,"musicVocalType":"future_vocal","characters":[{"characterId":2,"characterType":"outside_character"}],"releaseConditionId":4}]"#),
            outside: data(#"[{"id":2,"name":"Guest"}]"#), characters: data("[]"),
            conditions: data(#"[{"id":4,"sentence":"","releaseConditionType":"rank","releaseConditionTypeLevel":0}]"#))
        let song = try _Song(serializedBytes: songs[0].serializedData())
        XCTAssertEqual(song.composer, "Composer")
        XCTAssertEqual(song.lyricist, "Lyricist")
        XCTAssertEqual(song.arranger, "Arranger")
        XCTAssertEqual(song.tags, ["future_category"])
        XCTAssertEqual(song.media, ["mv"])
        XCTAssertTrue(song.hasPublishedAt)
        XCTAssertFalse(song.hasReleasedAt)
        XCTAssertEqual(song.charts[0].playLevel, 30)
        XCTAssertEqual(song.vocals[0].characters[0].name, "Guest")
        XCTAssertEqual(song.vocals[0].musicVocalType, "future_vocal")
        XCTAssertTrue(song.releaseCondition.hasSentence)
        XCTAssertTrue(song.releaseCondition.hasReleaseConditionTypeLevel)
    }

    func testFixtureKeepsAllBlueprintsAndZeroCost() throws {
        let rows = try convertFixtureArray(fixtures: data(#"[{"id":7,"name":"Fixture","seq":0,"gridSize":{"width":0,"height":2,"depth":3},"mysekaiFixtureMainGenreId":2}]"#),
            genres: data(#"[{"id":2,"name":"Genre"}]"#), subgenres: data("[]"),
            blueprints: data(#"[{"id":2,"craftTargetId":7,"mysekaiCraftType":"mysekai_fixture"},{"id":3,"craftTargetId":7,"mysekaiCraftType":"mysekai_fixture"}]"#),
            costs: data(#"[{"id":1,"mysekaiBlueprintId":3,"mysekaiMaterialId":4,"quantity":0}]"#), materials: data(#"[{"id":4,"name":"Material"}]"#))
        let fixture = try _Fixture(serializedBytes: rows[0].serializedData())
        XCTAssertTrue(fixture.hasSeq)
        XCTAssertEqual(fixture.mainGenre, "Genre")
        XCTAssertEqual(fixture.blueprints.count, 2)
        XCTAssertTrue(fixture.blueprints[0].materials.isEmpty)
        XCTAssertEqual(fixture.blueprints[1].materials[0].quantity, 0)
        XCTAssertFalse(fixture.blueprints[1].materials[0].hasAssetbundleName)
    }

    func testSkillPreservesFractionalDurationAndUnknownCategories() throws {
        let rows = try convertRows(data(#"[{"id":1,"skillEffects":[{"skillEffectType":"future","skillEffectDetails":[{"level":1,"activateEffectDuration":4.5,"activateEffectValueType":"future","activateEffectValue":20}]}]}]"#), table: "skills", as: _Skill.self)
        XCTAssertEqual(rows[0].skillEffects[0].skillEffectDetails[0].activateEffectDuration, 4.5)
        XCTAssertEqual(rows[0].skillEffects[0].skillEffectType, "future")
    }

    func testGachaRetainsPreciseRatesUnknownCategoriesAndPresence() throws {
        let row = try XCTUnwrap(convertGachaArray(data: data(#"[{"id":1,"spinLimit":0,"startAt":0,"gachaCardRarityRates":[{"cardRarityType":"future","lotteryType":"future","rate":0.123456789}],"gachaBehaviors":[{"id":1,"gachaBehaviorType":"future","costResourceType":"future","costResourceId":0}],"gachaDetails":[{"id":1,"cardId":2,"gachaDetailWishType":"future","fixedBonusWeight":0}]}]"#)).first)
        XCTAssertTrue(row.hasSpinLimit)
        XCTAssertFalse(row.hasDailySpinLimit)
        XCTAssertTrue(row.hasStartAt)
        XCTAssertFalse(row.hasEndAt)
        XCTAssertEqual(row.gachaCardRarityRates[0].preciseRate, 0.123456789)
        XCTAssertFalse(row.gachaCardRarityRates[0].hasID)
        XCTAssertEqual(row.gachaBehaviors[0].typeName, "future")
        XCTAssertTrue(row.gachaBehaviors[0].hasCostResourceID)
        XCTAssertTrue(row.gachaDetails[0].hasFixedBonusWeight)
        XCTAssertFalse(row.gachaInformation.hasSummary)
    }

    func testStatisticsRequireCompleteFiniteValuesAndUniqueChartKeys() throws {
        let row = #"{"music_id":1,"difficulty":"master","music_time":120.5,"base_score":1.25,"fever_score":0,"event_rate":100}"#
        let result = try convertMusicMetaArray(data("[" + row + "]"))
        XCTAssertEqual(result[0].musicTime, 120.5)
        XCTAssertEqual(result[0].feverScore, 0)
        XCTAssertThrowsError(try convertMusicMetaArray(data("[" + row + "," + row + "]")))
        XCTAssertThrowsError(try convertMusicMetaArray(data(#"[{"music_id":1,"difficulty":"master","music_time":120}]"#)))
    }

    func testStatisticsPreserveSourceDoubleBits() throws {
        let input = data(#"[{"music_id":1,"difficulty":"easy","music_time":123.2,"base_score":1.0052492944496712,"fever_score":0.22803386641580425,"event_rate":114}]"#)
        let row = try JSON(data: input)[0]
        let converted = try XCTUnwrap(convertMusicMetaArray(input).first)
        let decoded = try _MusicMeta(serializedBytes: converted.serializedData())
        XCTAssertEqual(decoded.baseScore.bitPattern, row["base_score"].doubleValue.bitPattern)
        XCTAssertEqual(decoded.feverScore.bitPattern, row["fever_score"].doubleValue.bitPattern)
        XCTAssertEqual(decoded.musicTime.bitPattern, row["music_time"].doubleValue.bitPattern)
    }

    func testEpisodeKindsAndRegionalScenarioPaths() throws {
        let cards = data(#"[{"id":1,"cardId":7,"title":"Card","scenarioId":"scenario","assetbundleName":"bundle"}]"#)
        let jp = try convertEpisodeArray(events: data("[]"), units: data("[]"), cards: cards, locale: .jp)
        let en = try convertEpisodeArray(events: data("[]"), units: data("[]"), cards: cards, locale: .en)
        XCTAssertEqual(jp[0].parentID, 7)
        XCTAssertEqual(jp[0].kind, "card")
        XCTAssertEqual(jp[0].scenarioPath, "character/member/bundle/scenario.asset")
        XCTAssertEqual(en[0].scenarioPath, "character/member_scenario/bundle/scenario.asset")
    }
}
