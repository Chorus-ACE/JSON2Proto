import Foundation
import SwiftyJSON
import SwiftProtobuf

extension _SongList: RegionalList {}
extension _VocalistList: RegionalList {}
extension _StickerList: RegionalList {}
extension _ComicList: RegionalList {}
extension _FixtureList: RegionalList {}
extension _SkillList: RegionalList {}
extension _ReleaseConditionList: RegionalList {}
extension _EpisodeList: RegionalList {}
extension _Character2DList: RegionalList {}

func convertRows<Message: SwiftProtobuf.Message>(_ data: Data, table: String, as: Message.Type) throws -> [Message] {
    let rows = try jsonRows(data, table: table)
    _ = try indexed(rows, key: "id", table: table)
    return try rows.map { try decode($0, as: Message.self) }
}

func convertFixtureArray(fixtures: Data, genres: Data, subgenres: Data, blueprints: Data, costs: Data, materials: Data) throws -> [_Fixture] {
    let rows = try jsonRows(fixtures, table: "mysekaiFixtures")
    _ = try indexed(rows, key: "id", table: "mysekaiFixtures")
    let genres = try indexed(jsonRows(genres, table: "mysekaiFixtureMainGenres"), key: "id", table: "mysekaiFixtureMainGenres")
    let subgenres = try indexed(jsonRows(subgenres, table: "mysekaiFixtureSubGenres"), key: "id", table: "mysekaiFixtureSubGenres")
    let blueprintRows = try jsonRows(blueprints, table: "mysekaiBlueprints")
    _ = try indexed(blueprintRows, key: "id", table: "mysekaiBlueprints")
    let grouped = Dictionary(grouping: blueprintRows.filter { $0["mysekaiCraftType"].string == "mysekai_fixture" }) { $0["craftTargetId"].intValue }
    let costs = try Dictionary(grouping: jsonRows(costs, table: "mysekaiBlueprintMysekaiMaterialCosts")) { $0["mysekaiBlueprintId"].intValue }
    let materials = try indexed(jsonRows(materials, table: "mysekaiMaterials"), key: "id", table: "mysekaiMaterials")
    return try rows.map { row in
        var result = try decode(row, as: _Fixture.self)
        if let id = row["mysekaiFixtureMainGenreId"].int, let name = genres[id]?["name"].string { result.mainGenre = name }
        if let id = row["mysekaiFixtureSubGenreId"].int, let name = subgenres[id]?["name"].string { result.subGenre = name }
        result.blueprints = try (grouped[result.id.int] ?? []).map { blueprint in
            var result = try decode(blueprint, as: _FixtureBlueprint.self)
            result.materials = try (costs[result.id.int] ?? []).map { cost in
                guard let id = cost["mysekaiMaterialId"].int, let quantity = cost["quantity"].int32 else {
                    throw ConversionError.invalidRecord("fixture materials", result.id.int, "Missing material or quantity")
                }
                return .with {
                    $0.id = Int32(id); $0.quantity = quantity
                    if let name = materials[id]?["name"].string { $0.name = name }
                    if let value = materials[id]?["iconAssetbundleName"].string { $0.assetbundleName = value }
                    if let value = cost["seq"].int32 { $0.seq = value }
                }
            }
            return result
        }
        return result
    }
}

private extension Int32 { var int: Int { Int(self) } }

func convertSongArray(musics: Data, tags: Data, charts: Data, artists: Data, vocals: Data, outside: Data, characters: Data, conditions: Data) throws -> [_Song] {
    let rows = try jsonRows(musics, table: "musics")
    _ = try indexed(rows, key: "id", table: "musics")
    let tags = try Dictionary(grouping: jsonRows(tags, table: "musicTags")) { $0["musicId"].intValue }
    let charts = try Dictionary(grouping: jsonRows(charts, table: "musicDifficulties")) { $0["musicId"].intValue }
    let artists = try indexed(jsonRows(artists, table: "musicArtists"), key: "id", table: "musicArtists")
    let vocalRows = try jsonRows(vocals, table: "musicVocals")
    _ = try indexed(vocalRows, key: "id", table: "musicVocals")
    let vocals = Dictionary(grouping: vocalRows) { $0["musicId"].intValue }
    let outside = try indexed(jsonRows(outside, table: "outsideCharacters"), key: "id", table: "outsideCharacters")
    let characters = try indexed(jsonRows(characters, table: "gameCharacters"), key: "id", table: "gameCharacters")
    let conditions = try indexed(jsonRows(conditions, table: "releaseConditions"), key: "id", table: "releaseConditions")
    return try rows.map { source in
        var row = source
        // Older regional tables store text credits in infos and media as objects.
        if let info = row["infos"].array?.first {
            for key in ["title", "creator", "composer", "arranger", "lyricist"] { row[key] = info[key] }
        } else { row["creator"] = artists[row["creatorArtistId"].intValue]?["name"] ?? JSON("") }
        row["media"] = JSON(row["categories"].arrayValue.compactMap { $0.string ?? $0["musicCategoryName"].string })
        row["tags"] = JSON((tags[row["id"].intValue] ?? []).compactMap { $0["musicTag"].string })
        row["charts"] = JSON(charts[row["id"].intValue] ?? [])
        // Normalize legacy upper-case ID spellings to the schema's canonical JSON names.
        for key in ["liveStage", "releaseCondition"] where row[key + "Id"] == .null { row[key + "Id"] = row[key + "ID"] }
        var song = try decode(row, as: _Song.self)
        if let condition = conditions[song.releaseConditionID.int] { song.releaseCondition = try decode(condition, as: _ReleaseCondition.self) }
        song.vocals = try (vocals[song.id.int] ?? []).map { row in
            var normalized = row
            normalized["characters"] = JSON([])
            var vocal = try decode(normalized, as: _SongVocal.self)
            if let condition = conditions[vocal.releaseConditionID.int] { vocal.releaseCondition = try decode(condition, as: _ReleaseCondition.self) }
            vocal.characters = row["characters"].arrayValue.compactMap { entry in
                guard let id = entry["characterId"].int32 else { return nil }
                let internalCharacter = entry["characterType"].string == "game_character"
                let record = internalCharacter ? characters[id.int] : outside[id.int]
                return .with {
                    $0.id = id; $0.isInternal = internalCharacter
                    if let record {
                        if internalCharacter {
                            $0.name = [record["firstName"].string, record["givenName"].string].compactMap { $0 }.joined(separator: " ")
                        } else if let name = record["name"].string { $0.name = name }
                    }
                }
            }
            return vocal
        }
        return song
    }
}

func convertEpisodeArray(events: Data, units: Data, cards: Data, locale: MasterLocale) throws -> [_Episode] {
    var result: [_Episode] = []
    func append(_ row: JSON, parent: Int32, kind: String, chapter: String, bundle: String) throws {
        guard let id = row["id"].int32, let title = row["title"].string,
              let scenario = row["scenarioId"].string, !scenario.isEmpty else {
            throw ConversionError.invalidRecord("episodes", row["id"].intValue, "Missing id, title or scenario")
        }
        var episode = _Episode.with {
            $0.id = id; $0.parentID = parent; $0.kind = kind; $0.number = row["episodeNo"].int32 ?? row["seq"].int32 ?? 0
            $0.title = title; $0.chapterTitle = chapter; $0.scenarioID = scenario
        }
        switch kind {
        case "event":
            episode.scenarioPath = "event_story/\(bundle)/scenario/\(scenario).asset"
            if let cover = row["assetbundleName"].string { episode.imagePath = "event_story/\(bundle)/episode_image/\(cover).webp" }
        case "unit":
            episode.scenarioPath = "scenario/unitstory/\(bundle)/\(scenario).asset"
            if let cover = row["assetbundleName"].string { episode.imagePath = "story/episode_image/\(bundle)/\(cover).webp" }
        default:
            episode.scenarioPath = "character/\(locale == .en ? "member_scenario" : "member")/\(bundle)/\(scenario).asset"
            episode.imagePath = "character/member_small/\(bundle)/card_normal.webp"
        }
        result.append(episode)
    }
    for story in try jsonRows(events, table: "eventStories") {
        for row in story["eventStoryEpisodes"].arrayValue { try append(row, parent: story["eventId"].int32Value, kind: "event", chapter: story["outline"].stringValue, bundle: story["assetbundleName"].stringValue) }
    }
    for unit in try jsonRows(units, table: "unitStories") {
        for chapter in unit["chapters"].arrayValue {
            for row in chapter["episodes"].arrayValue { try append(row, parent: chapter["id"].int32Value, kind: "unit", chapter: chapter["title"].stringValue, bundle: chapter["assetbundleName"].stringValue) }
        }
    }
    for row in try jsonRows(cards, table: "cardEpisodes") {
        // Some master records are placeholders with no downloadable scenario.
        guard let bundle = row["assetbundleName"].string, !bundle.isEmpty else { continue }
        try append(row, parent: row["cardId"].int32Value, kind: "card", chapter: "", bundle: bundle)
    }
    guard Set(result.map { "\($0.kind)-\($0.id)" }).count == result.count else { throw ConversionError.invalidRecord("episodes", 0, "Duplicate kind/id") }
    return result
}

func convertMusicMetaArray(_ data: Data) throws -> [_MusicMeta] {
    var keys: Set<String> = []
    return try jsonRows(data, table: "music_metas").map { row in
        guard let id = row["music_id"].int, id > 0,
              let difficulty = row["difficulty"].string, !difficulty.isEmpty,
              let duration = row["music_time"].double, duration.isFinite, duration > 0,
              let base = row["base_score"].double, base.isFinite,
              let fever = row["fever_score"].double, fever.isFinite,
              let rate = row["event_rate"].double, rate.isFinite,
              keys.insert("\(id)-\(difficulty)").inserted else {
            throw ConversionError.invalidRecord("music_metas", row["music_id"].intValue, "Invalid or duplicate chart statistics")
        }
        // Avoid a second JSON serialization/parser round-trip changing the last bit
        // of source doubles. The validated values are already the client representation.
        return .with {
            $0.musicID = Int32(id); $0.difficulty = difficulty; $0.musicTime = duration
            $0.baseScore = base; $0.feverScore = fever; $0.eventRate = rate
        }
    }
}

func convertAdditionalLists(to output: URL, source: MasterDataSource) async throws {
    try await writeList(_StickerList.self, to: output.appending(path: "sticker.proto")) { locale in
        try await convertRows(source.data("stamps", locale: locale), table: "stamps", as: _Sticker.self)
    }
    try await writeList(_ComicList.self, to: output.appending(path: "comic.proto")) { locale in
        let rows = try await jsonRows(source.data("tips", locale: locale), table: "tips")
        _ = try indexed(rows, key: "id", table: "tips")
        return try rows.filter { $0["assetbundleName"].string?.hasPrefix("comic_") == true }.map { try decode($0, as: _Comic.self) }
    }
    try await writeList(_SkillList.self, to: output.appending(path: "skill.proto")) { locale in
        try await convertRows(source.data("skills", locale: locale), table: "skills", as: _Skill.self)
    }
    try await writeList(_ReleaseConditionList.self, to: output.appending(path: "release_condition.proto")) { locale in
        try await convertRows(source.data("releaseConditions", locale: locale), table: "releaseConditions", as: _ReleaseCondition.self)
    }
    try await writeList(_FixtureList.self, to: output.appending(path: "fixture.proto")) { locale in
        async let fixtures = source.data("mysekaiFixtures", locale: locale)
        async let genres = source.data("mysekaiFixtureMainGenres", locale: locale)
        async let subgenres = source.data("mysekaiFixtureSubGenres", locale: locale)
        async let blueprints = source.data("mysekaiBlueprints", locale: locale)
        async let costs = source.data("mysekaiBlueprintMysekaiMaterialCosts", locale: locale)
        async let materials = source.data("mysekaiMaterials", locale: locale)
        return try await convertFixtureArray(fixtures: fixtures, genres: genres, subgenres: subgenres, blueprints: blueprints, costs: costs, materials: materials)
    }
    let songURL = output.appending(path: "song.proto")
    try await writeList(_SongList.self, to: songURL) { locale in
        async let musics = source.data("musics", locale: locale)
        async let tags = source.data("musicTags", locale: locale)
        async let charts = source.data("musicDifficulties", locale: locale)
        async let artists = [MasterLocale.jp, .en].contains(locale) ? source.data("musicArtists", locale: locale) : Data("[]".utf8)
        async let vocals = source.data("musicVocals", locale: locale)
        async let outside = source.data("outsideCharacters", locale: locale)
        async let characters = source.data("gameCharacters", locale: locale)
        async let conditions = source.data("releaseConditions", locale: locale)
        return try await convertSongArray(musics: musics, tags: tags, charts: charts, artists: artists, vocals: vocals, outside: outside, characters: characters, conditions: conditions)
    }
    var songs = try _SongList(serializedBytes: Data(contentsOf: songURL))
    let outsideURL = output.appending(path: "outside.tmp")
    try await writeList(_VocalistList.self, to: outsideURL) { locale in
        try await convertRows(source.data("outsideCharacters", locale: locale), table: "outsideCharacters", as: _Vocalist.self)
    }
    songs.outsideCharacters = try _VocalistList(serializedBytes: Data(contentsOf: outsideURL))
    try FileManager.default.removeItem(at: outsideURL)
    let metaData: Data
    if let input = source.inputFolder { metaData = try Data(contentsOf: input.appending(path: "shared/music_metas.json")) }
    else {
        let url = URL(string: "https://storage.sekai.best/sekai-best-assets/music_metas.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw ConversionError.invalidResponse(url, (response as? HTTPURLResponse)?.statusCode ?? 0) }
        metaData = data
    }
    songs.musicMeta = try convertMusicMetaArray(metaData)
    try songs.serializedData().write(to: songURL, options: .atomic)
    let episodeURL = output.appending(path: "episode.proto")
    try await writeList(_EpisodeList.self, to: episodeURL) { locale in
        async let events = source.data("eventStories", locale: locale)
        async let units = source.data("unitStories", locale: locale)
        async let cards = source.data("cardEpisodes", locale: locale)
        return try await convertEpisodeArray(events: events, units: units, cards: cards, locale: locale)
    }
    var episodes = try _EpisodeList(serializedBytes: Data(contentsOf: episodeURL))
    let modelsURL = output.appending(path: "models.tmp")
    try await writeList(_Character2DList.self, to: modelsURL) { locale in
        try await convertRows(source.data("character2ds", locale: locale), table: "character2ds", as: _Character2D.self)
    }
    episodes.characterModels = try _Character2DList(serializedBytes: Data(contentsOf: modelsURL))
    try FileManager.default.removeItem(at: modelsURL)
    try episodes.serializedData().write(to: episodeURL, options: .atomic)
}
