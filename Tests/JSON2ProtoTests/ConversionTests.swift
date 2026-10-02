import Foundation
import XCTest
import SwiftProtobuf
@testable import JSON2Proto

final class ConversionTests: XCTestCase {
    private func data(_ string: String) -> Data { Data(string.utf8) }

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
