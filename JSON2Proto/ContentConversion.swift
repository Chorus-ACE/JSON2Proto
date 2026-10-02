import Foundation
import SwiftProtobuf
import SwiftyJSON

enum ConversionError: Error {
    case invalidResponse(URL, Int)
    case expectedArray(String)
    case invalidID(String)
    case duplicateID(String, Int)
    case missingCharacter(Int)
    case invalidRecord(String, Int, String)
    case localeFailed(String, String)
}

enum MasterLocale: String, CaseIterable {
    case jp, en, tc, cn, kr

    var databasePath: String {
        self == .jp ? "sekai-master-db-diff" : "sekai-master-db-\(rawValue)-diff"
    }
}

struct MasterDataSource {
    // Offline input uses <folder>/<jp|en|tc|cn|kr>/<table>.json.
    var inputFolder: URL?

    func data(_ table: String, locale: MasterLocale) async throws -> Data {
        if let inputFolder {
            return try Data(contentsOf: inputFolder.appending(path: locale.rawValue).appending(path: "\(table).json"))
        }
        let url = URL(string: "https://raw.githubusercontent.com/Sekai-World/\(locale.databasePath)/refs/heads/main/\(table).json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ConversionError.invalidResponse(url, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

protocol RegionalList: SwiftProtobuf.Message {
    associatedtype Item
    var jp: [Item] { get set }
    var en: [Item] { get set }
    var tc: [Item] { get set }
    var cn: [Item] { get set }
    var kr: [Item] { get set }
}

extension _GachaList: RegionalList {}
extension _CharacterList: RegionalList {}
extension _EventList: RegionalList {}
extension _CardList: RegionalList {}

func writeList<List: RegionalList>(
    _ type: List.Type, to url: URL,
    load: (MasterLocale) async throws -> [List.Item]
) async throws {
    var list = List()
    for locale in MasterLocale.allCases {
        let items: [List.Item]
        do {
            items = try await load(locale)
        } catch {
            throw ConversionError.localeFailed(locale.rawValue, String(describing: error))
        }
        print("\(List.self) [\(locale.rawValue)]: \(items.count) records")
        switch locale {
        case .jp: list.jp = items
        case .en: list.en = items
        case .tc: list.tc = items
        case .cn: list.cn = items
        case .kr: list.kr = items
        }
    }
    try list.serializedData().write(to: url, options: .atomic)
}

func jsonRows(_ data: Data, table: String) throws -> [JSON] {
    guard let rows = try JSON(data: data).array else {
        throw ConversionError.expectedArray(table)
    }
    return rows
}

private func indexed(_ rows: [JSON], key: String, table: String) throws -> [Int: JSON] {
    var result: [Int: JSON] = [:]
    for row in rows {
        guard let id = row[key].int, id > 0 else { throw ConversionError.invalidID(table) }
        guard result.updateValue(row, forKey: id) == nil else { throw ConversionError.duplicateID(table, id) }
    }
    return result
}

private func decode<Message: SwiftProtobuf.Message>(_ json: JSON, as type: Message.Type) throws -> Message {
    var options = JSONDecodingOptions()
    options.ignoreUnknownFields = true
    do {
        return try Message(jsonUTF8Data: json.rawData(), options: options)
    } catch {
        throw ConversionError.invalidRecord(String(describing: type), json["id"].intValue, String(describing: error))
    }
}

func convertCharacterArray(profiles: Data, characters: Data, units: Data) throws -> [_Character] {
    let profiles = try jsonRows(profiles, table: "characterProfiles")
    let characters = try indexed(jsonRows(characters, table: "gameCharacters"), key: "id", table: "gameCharacters")
    let units = try Dictionary(grouping: jsonRows(units, table: "gameCharacterUnits")) { $0["gameCharacterId"].intValue }
    _ = try indexed(profiles, key: "characterId", table: "characterProfiles")
    return try profiles.map { profile in
        let id = profile["characterId"].intValue
        guard let character = characters[id] else { throw ConversionError.missingCharacter(id) }
        // gameCharacters.height is numeric; characterProfiles.height is display text.
        var merged = profile.dictionaryValue.merging(character.dictionaryValue) { _, characterValue in characterValue }
        merged["colorInfo"] = JSON(units[id] ?? [])
        return try decode(JSON(merged), as: _Character.self)
    }
}

func convertCardArray(data: Data) throws -> [_Card] {
    let rows = try jsonRows(data, table: "cards")
    _ = try indexed(rows, key: "id", table: "cards")
    return try rows.map { row in
        var row = row
        // TC/CN/KR publish compact parameter arrays keyed by type. JP/EN
        // publish individual records. Normalize both to explicit level/power pairs.
        if let compact = row["cardParameters"].dictionary {
            var parameters: [JSON] = []
            for type in compact.keys.sorted() {
                guard let powers = compact[type]?.array else {
                    throw ConversionError.invalidRecord("cards", row["id"].intValue, "Invalid cardParameters.\(type)")
                }
                for (index, power) in powers.enumerated() {
                    parameters.append(JSON([
                        "cardParameterType": JSON(type), "cardLevel": JSON(index + 1), "power": power
                    ]))
                }
            }
            row["cardParameters"] = JSON(parameters)
        }
        return try decode(row, as: _Card.self)
    }
}

func convertEventArray(events: Data, bonuses: Data, cards: Data, musics: Data) throws -> [_Event] {
    let rows = try jsonRows(events, table: "events")
    _ = try indexed(rows, key: "id", table: "events")
    let bonuses = try Dictionary(grouping: jsonRows(bonuses, table: "eventDeckBonuses")) { $0["eventId"].intValue }
    let cards = try Dictionary(grouping: jsonRows(cards, table: "eventCards")) { $0["eventId"].intValue }
    let musics = try Dictionary(grouping: jsonRows(musics, table: "eventMusics")) { $0["eventId"].intValue }
    return try rows.map { row in
        var event = try decode(row, as: _Event.self)
        let id = Int(event.id)
        for bonus in bonuses[id] ?? [] {
            let character = bonus["gameCharacterUnitId"].int32
            let attribute = bonus["cardAttr"].string
            if let character, attribute == nil {
                // Unit-specific virtual singers share the same character in SekaiKit.
                let mapped = (27...56).contains(character) ? 21 + (character - 27) / 5 : character
                if !event.characters.contains(mapped) { event.characters.append(mapped) }
                event.characterBonus = bonus["bonusRate"].int32Value
            } else if let attribute, character == nil {
                event.attribute = attribute
                event.attributeBonus = bonus["bonusRate"].int32Value
            }
        }
        event.cardIds = (cards[id] ?? []).map { $0["cardId"].int32Value }
        event.musicIds = (musics[id] ?? []).map { $0["musicId"].int32Value }
        return event
    }
}

func convertCharacterList(to url: URL, source: MasterDataSource) async throws {
    try await writeList(_CharacterList.self, to: url) { locale in
        async let profiles = source.data("characterProfiles", locale: locale)
        async let characters = source.data("gameCharacters", locale: locale)
        async let units = source.data("gameCharacterUnits", locale: locale)
        return try await convertCharacterArray(profiles: profiles, characters: characters, units: units)
    }
}

func convertEventList(to url: URL, source: MasterDataSource) async throws {
    try await writeList(_EventList.self, to: url) { locale in
        async let events = source.data("events", locale: locale)
        async let bonuses = source.data("eventDeckBonuses", locale: locale)
        async let cards = source.data("eventCards", locale: locale)
        async let musics = source.data("eventMusics", locale: locale)
        return try await convertEventArray(events: events, bonuses: bonuses, cards: cards, musics: musics)
    }
}

func convertCardList(to url: URL, source: MasterDataSource) async throws {
    try await writeList(_CardList.self, to: url) { locale in
        try await convertCardArray(data: source.data("cards", locale: locale))
    }
}
