import Foundation
import XCTest
import SwiftProtobuf
@testable import JSON2Proto

final class ConversionTests: XCTestCase {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testGachaMetadataCategoriesAndOptionalLimits() throws {
        let rows = try convertGachaArray(data: data(#"[{"id":1,"gachaType":"subeginner","gachaInformation":{"summary":"Summary","description":"Rules"},"gachaBehaviors":[{"id":1,"executeLimit":0},{"id":2}]},{"id":2,"gachaType":"sureturn"},{"id":3,"gachaType":"sunormal"},{"id":4,"gachaType":"return"},{"id":5,"gachaType":"future_type"}]"#))
        let first = try _Gacha(serializedBytes: rows[0].serializedData())
        XCTAssertEqual(first.gachaInformation.gachaID, 1)
        XCTAssertEqual(first.gachaInformation.summary, "Summary")
        XCTAssertEqual(first.gachaInformation.description_p, "Rules")
        XCTAssertTrue(first.gachaBehaviors[0].hasExecuteLimit)
        XCTAssertEqual(first.gachaBehaviors[0].executeLimit, 0)
        XCTAssertFalse(first.gachaBehaviors[1].hasExecuteLimit)
        XCTAssertEqual(rows.prefix(4).map(\.gachaType), [.specialBeginner, .specialReturn, .specialNormal, .returning])
        XCTAssertEqual(rows[4].gachaTypeName, "future_type")
        XCTAssertThrowsError(try convertGachaArray(data: data(#"[{"id":1},{"id":1}]"#)))
        XCTAssertThrowsError(try convertGachaArray(data: data(#"[{"name":"Missing ID"}]"#)))
    }

    // Deliberately shuffled; banner unit IDs must be joined, not treated as character IDs.
    private var focusEvents: Data {
        data(#"[{"id":150,"unit":"school_refusal","startAt":500},{"id":127,"unit":"school_refusal","startAt":400},{"id":14,"unit":"none","startAt":100},{"id":53,"unit":"school_refusal","startAt":200},{"id":77,"unit":"school_refusal","startAt":300},{"id":22,"unit":"none","startAt":150},{"id":112,"unit":"school_refusal","eventType":"world_bloom","startAt":350},{"id":1,"unit":"none","startAt":50}]"#)
    }
    private var focusStories: Data {
        data(#"[{"eventId":150,"bannerGameCharacterUnitId":119},{"eventId":127,"bannerGameCharacterUnitId":119},{"eventId":14,"bannerGameCharacterUnitId":119},{"eventId":53,"bannerGameCharacterUnitId":119},{"eventId":77,"bannerGameCharacterUnitId":119},{"eventId":22,"bannerGameCharacterUnitId":119},{"eventId":112,"bannerGameCharacterUnitId":119},{"eventId":1,"bannerGameCharacterUnitId":2}]"#)
    }
    private var focusUnits: Data {
        data(#"[{"id":119,"gameCharacterId":19,"unit":"school_refusal"},{"id":2,"gameCharacterId":2,"unit":"light_sound"}]"#)
    }

    func testFocusCountsExcludeMixedAndWorldLinkEvents() throws {
        let focus = try calculateEventFocus(events: focusEvents, stories: focusStories, units: focusUnits)
        XCTAssertEqual([14, 53, 77, 127, 150].map { focus[$0]?.index }, [1, 2, 3, 4, 5])
        XCTAssertEqual(focus[150]?.characterID, 19)
        XCTAssertEqual(focus[1]?.characterID, 2)
        XCTAssertEqual(focus[1]?.index, 1)
        XCTAssertNil(focus[22])
        XCTAssertNil(focus[112])
        let chronological = try calculateEventFocus(
            events: data(#"[{"id":60,"unit":"school_refusal","startAt":1},{"id":50,"unit":"school_refusal","startAt":2}]"#),
            stories: data(#"[{"eventId":60,"bannerGameCharacterUnitId":119},{"eventId":50,"bannerGameCharacterUnitId":119}]"#),
            units: focusUnits
        )
        XCTAssertEqual(chronological[60]?.index, 1)
        XCTAssertEqual(chronological[50]?.index, 2)
    }

    func testIncompleteFocusDataFailsInsteadOfUndercounting() {
        XCTAssertThrowsError(try calculateEventFocus(events: focusEvents, stories: data("[]"), units: focusUnits))
        XCTAssertThrowsError(try calculateEventFocus(events: focusEvents, stories: focusStories, units: data("[]")))
        XCTAssertThrowsError(try calculateEventFocus(
            events: data(#"[{"id":53,"unit":"school_refusal","startAt":1}]"#),
            stories: data(#"[{"eventId":53,"bannerGameCharacterUnitId":2}]"#), units: focusUnits
        ))
    }

    func testRegionalFocusUsesFullJapaneseHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for locale in MasterLocale.allCases {
            let folder = directory.appending(path: locale.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Other regions have only the fifth event and use different dates.
            try (locale == .jp ? focusEvents : data(#"[{"id":150,"unit":"school_refusal","startAt":1},{"id":22,"unit":"none"}]"#))
                .write(to: folder.appending(path: "events.json"))
            for table in ["eventDeckBonuses", "eventCards", "eventMusics"] {
                try data("[]").write(to: folder.appending(path: "\(table).json"))
            }
        }
        try focusStories.write(to: directory.appending(path: "jp/eventStories.json"))
        try focusUnits.write(to: directory.appending(path: "jp/gameCharacterUnits.json"))
        let output = directory.appending(path: "event.proto")
        try await convertEventList(to: output, source: MasterDataSource(inputFolder: directory))
        let list = try _EventList(serializedBytes: Data(contentsOf: output))
        for region in [list.jp, list.en, list.tc, list.cn, list.kr] {
            let event = try XCTUnwrap(region.first { $0.id == 150 })
            XCTAssertEqual(event.focusCharacterID, 19)
            XCTAssertEqual(event.focusCharacterIndex, 5)
            let mixed = try XCTUnwrap(region.first { $0.id == 22 })
            XCTAssertFalse(mixed.hasFocusCharacterID)
            XCTAssertFalse(mixed.hasFocusCharacterIndex)
        }
    }

    func testCharacterJoinUsesIDsAndPreservesMissingNames() throws {
        let characters = try convertCharacterArray(
            profiles: data(#"[{"characterId":2,"birthday":"8月31日","height":"158cm","school":""},{"characterId":1}]"#),
            characters: data(#"[{"id":1,"givenName":"一歌"},{"id":2,"givenName":"ミク","height":158,"live2dHeightAdjustment":1.5}]"#),
            units: data(##"[{"id":40,"gameCharacterId":2,"unit":"piapro","colorCode":"#33CCBB"}]"##)
        )
        let list = _CharacterList.with { $0.jp = characters }
        let decoded = try _CharacterList(serializedBytes: list.serializedData())
        XCTAssertEqual(decoded.jp.map(\.id), [2, 1])
        XCTAssertEqual(decoded.jp[0].givenName, "ミク")
        XCTAssertEqual(decoded.jp[0].height, 158)
        XCTAssertEqual(decoded.jp[0].colorInfo.first?.id, 40)
        XCTAssertFalse(decoded.jp[0].hasFamilyName)
        XCTAssertTrue(decoded.jp[0].hasSchool)
        XCTAssertFalse(decoded.jp[1].hasSchool)
    }

    func testBrokenCharacterJoinFails() {
        XCTAssertThrowsError(try convertCharacterArray(
            profiles: data(#"[{"characterId":2}]"#), characters: data(#"[{"id":1}]"#), units: data("[]")
        ))
    }

    func testEventBonusesRewardsAndAssociations() throws {
        let events = try convertEventArray(
            events: data(#"[{"id":7,"name":"イベント","startAt":1700000000123,"assetbundleName":"event_a","bgmAssetbundleName":"bgm_a","eventRankingRewardRanges":[{"fromRank":1,"toRank":100,"isToRankBorder":true,"eventRankingRewards":[{"resourceBoxId":10}]}]},{"id":8}]"#),
            bonuses: data(#"[{"eventId":7,"gameCharacterUnitId":27,"bonusRate":25},{"eventId":7,"gameCharacterUnitId":31,"bonusRate":25},{"eventId":7,"gameCharacterUnitId":32,"bonusRate":25},{"eventId":7,"cardAttr":"cool","bonusRate":50},{"eventId":7,"gameCharacterUnitId":1,"cardAttr":"cool","bonusRate":100}]"#),
            cards: data(#"[{"eventId":7,"cardId":42},{"eventId":8,"cardId":43}]"#),
            musics: data(#"[{"eventId":7,"musicId":12}]"#)
        )
        let decoded = try _Event(serializedBytes: events[0].serializedData())
        XCTAssertEqual(decoded.characters, [21, 22])
        XCTAssertEqual(decoded.attribute, "cool")
        XCTAssertEqual(decoded.attributeBonus, 50)
        XCTAssertEqual(decoded.characterBonus, 25)
        XCTAssertEqual(decoded.startAt, 1700000000123)
        XCTAssertFalse(decoded.hasClosedAt)
        XCTAssertEqual(decoded.bgmAssetbundleName, "bgm_a")
        XCTAssertEqual(decoded.cardIds, [42])
        XCTAssertEqual(decoded.musicIds, [12])
        XCTAssertEqual(decoded.eventRankingRewardRanges.first?.lowerBound, 100)
        XCTAssertFalse(decoded.eventRankingRewardRanges[0].eventRankingRewards[0].hasRewardConditionType)
        XCTAssertFalse(events[1].hasAttributeBonus)
    }

    func testHistoricalEventUnitsAndPatchBoundary() throws {
        let events = try convertEventArray(
            events: data(#"[{"id":1,"unit":"none"},{"id":14},{"id":8,"unit":"none"},{"id":37,"unit":"street"},{"id":41,"unit":"none"},{"id":42,"unit":"none"},{"id":43,"unit":"idol"},{"id":44},{"id":45,"unit":"none"}]"#),
            bonuses: data("[]"), cards: data("[]"), musics: data("[]")
        )
        let decoded = try events.map { try _Event(serializedBytes: $0.serializedData()) }
        XCTAssertEqual(decoded.map(\.unit), [
            "light_sound", "school_refusal", "theme_park", "street",
            "none", "none", "idol", "", "none"
        ])
        XCTAssertTrue(decoded[1].hasUnit)
        XCTAssertFalse(decoded[7].hasUnit)
        XCTAssertEqual(Set(EarlyEventUnits.corrections.keys), Set(1...42))
    }

    func testHistoricalUnitsAreAppliedToAllRegions() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeList(_EventList.self, to: url) { _ in
            try convertEventArray(
                events: self.data(#"[{"id":1,"unit":"none"},{"id":14,"unit":"none"},{"id":4,"unit":"none"},{"id":43,"unit":"idol"}]"#),
                bonuses: self.data("[]"), cards: self.data("[]"), musics: self.data("[]")
            )
        }
        let list = try _EventList(serializedBytes: Data(contentsOf: url))
        for region in [list.jp, list.en, list.tc, list.cn, list.kr] {
            XCTAssertEqual(region.map(\.unit), ["light_sound", "school_refusal", "none", "idol"])
        }
    }

    func testCardOptionalScalarsAndParametersRoundTrip() throws {
        let cards = try convertCardArray(data: data(#"[{"id":1,"prefix":"","releaseAt":1700000000123,"specialTrainingSkillId":0,"specialTrainingPower1BonusFixed":10,"cardParameters":[{"cardParameterType":"param1","cardLevel":60,"power":2000}],"futureField":true},{"id":2}]"#))
        let card = try _Card(serializedBytes: cards[0].serializedData())
        XCTAssertTrue(card.hasName)
        XCTAssertEqual(card.name, "")
        XCTAssertTrue(card.hasSpecialTrainingSkillID)
        XCTAssertEqual(card.specialTrainingSkillID, 0)
        XCTAssertEqual(card.releaseAt, 1700000000123)
        XCTAssertEqual(card.cardParameters[0].power, 2000)
        XCTAssertFalse(cards[1].hasName)
        XCTAssertFalse(cards[1].hasSpecialTrainingSkillID)
        XCTAssertFalse(cards[1].hasArchivePublishedAt)
    }

    func testInvalidInputCannotPublishEmptySuccess() {
        XCTAssertThrowsError(try convertCardArray(data: data(#"{"message":"Not Found"}"#)))
        XCTAssertThrowsError(try convertCardArray(data: data(#"[{"id":1},{"id":1}]"#)))
        XCTAssertThrowsError(try convertCardArray(data: data(#"[{"prefix":"no id"}]"#)))
        XCTAssertThrowsError(try convertGachaArray(data: data("null")))
    }

    func testCompactCardParametersMatchExpandedParameters() throws {
        let compact = try convertCardArray(data: data(#"[{"id":1,"cardParameters":{"param1":[1065,1149],"param2":[930]}}]"#))
        let expanded = try convertCardArray(data: data(#"[{"id":1,"cardParameters":[{"cardParameterType":"param1","cardLevel":1,"power":1065},{"cardParameterType":"param1","cardLevel":2,"power":1149},{"cardParameterType":"param2","cardLevel":1,"power":930}]}]"#))
        XCTAssertEqual(compact, expanded)
        XCTAssertThrowsError(try convertCardArray(data: data(#"[{"id":1,"cardParameters":{"param1":"invalid"}}]"#)))
    }

    func testAllFiveRegionsAreWritten() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeList(_CardList.self, to: url) { locale in
            [_Card.with { $0.id = 1; $0.name = locale.rawValue }]
        }
        let list = try _CardList(serializedBytes: Data(contentsOf: url))
        XCTAssertEqual([list.jp, list.en, list.tc, list.cn, list.kr].map { $0.first?.name }, ["jp", "en", "tc", "cn", "kr"])
    }
}
