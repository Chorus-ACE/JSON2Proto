//
//  WorkList.swift
//  JSON2Proto
//
//  Created by memz233 on 8/20/26.
//

import Foundation
import SwiftyJSON
import SwiftProtobuf

func convertGachaList(to url: URL, source: MasterDataSource) async throws {
    try await writeList(_GachaList.self, to: url) { locale in
        try await convertGachaArray(data: source.data("gachas", locale: locale))
    }
}

func convertGachaArray(data: Data) throws -> [_Gacha] {
    let json = try jsonRows(data, table: "gachas")
    _ = try indexed(json, key: "id", table: "gachas")
    
    var result: [_Gacha] = []
    result.reserveCapacity(json.count)
    for gachaJSON in json {
        var gacha = _Gacha()
        gacha.id = gachaJSON["id"].int32Value
        if let type = gachaJSON["gachaType"].string { gacha.gachaTypeName = type }
        switch gachaJSON["gachaType"].stringValue {
        case "normal":
            gacha.gachaType = .normal
        case "ceil":
            gacha.gachaType = .ceil
        case "gift":
            gacha.gachaType = .gift
        case "beginner":
            gacha.gachaType = .beginner
        case "subeginner":
            gacha.gachaType = .specialBeginner
        case "sureturn":
            gacha.gachaType = .specialReturn
        case "sunormal":
            gacha.gachaType = .specialNormal
        case "return":
            gacha.gachaType = .returning
        default: break
        }
        gacha.name = gachaJSON["name"].stringValue
        gacha.seq = gachaJSON["seq"].int32Value
        gacha.assetBundleName = gachaJSON["assetbundleName"].stringValue
        gacha.gachaCardRarityRateGroupID = gachaJSON["gachaCardRarityRateGroupId"].int32Value
        if let value = gachaJSON["startAt"].int64 { gacha.startAt = value }
        if let value = gachaJSON["endAt"].int64 { gacha.endAt = value }
        gacha.isShowPeriod = gachaJSON["isShowPeriod"].boolValue
        if let value = gachaJSON["gachaCeilItemId"].int32 { gacha.gachaCeilItemID = value }
        if let value = gachaJSON["spinLimit"].int32 { gacha.spinLimit = value }
        if let value = gachaJSON["dailySpinLimit"].int32 { gacha.dailySpinLimit = value }
        if let value = gachaJSON["drawableGachaHour"].int32 { gacha.drawableGachaHour = value }
        gacha.wishSelectCount = gachaJSON["wishSelectCount"].int32Value
        gacha.wishFixedSelectCount = gachaJSON["wishFixedSelectCount"].int32Value
        gacha.wishLimitedSelectCount = gachaJSON["wishLimitedSelectCount"].int32Value
        gacha.isSelectCharacter = gachaJSON["isSelectCharacter"].boolValue
        gacha.gachaCardRarityRates = gachaJSON["gachaCardRarityRates"].map {
            var result = _GachaCardRarityRate()
            if let value = $0.1["id"].int32 { result.id = value }
            if let value = $0.1["groupId"].int32 { result.groupID = value }
            switch $0.1["cardRarityType"].stringValue {
            case "rarity_2":
                result.cardRarityType = .rarity2
            case "rarity_3":
                result.cardRarityType = .rarity3
            case "rarity_4":
                result.cardRarityType = .rarity4
            case "rarity_birthday":
                result.cardRarityType = .rarityBirthday
            default: break
            }
            switch $0.1["lotteryType"].string {
            case "normal":
                result.lotteryType = .normal
            case "categorized_wish":
                result.lotteryType = .categorizedWish
            case "rate_choice_first":
                result.lotteryType = .rateChoiceFirst
            case "rate_choice_second":
                result.lotteryType = .rateChoiceSecond
            default: break
            }
            result.rate = $0.1["rate"].floatValue
            if let value = $0.1["rate"].double { result.preciseRate = value }
            if let value = $0.1["cardRarityType"].string { result.rarityName = value }
            if let value = $0.1["lotteryType"].string { result.lotteryName = value }
            return result
        }
        gacha.gachaDetails = gachaJSON["gachaDetails"].map {
            var result = _GachaDetail()
            result.id = $0.1["id"].int32Value
            result.gachaID = $0.1["gachaId"].int32Value
            result.cardID = $0.1["cardId"].int32Value
            result.weight = $0.1["weight"].int32Value
            result.isWish = $0.1["isWish"].boolValue
            if let value = $0.1["gachaDetailWishType"].string { result.wishType = value }
            if let value = $0.1["fixedBonusWeight"].int32 { result.fixedBonusWeight = value }
            return result
        }
        gacha.gachaBehaviors = gachaJSON["gachaBehaviors"].map {
            var result = _GachaBehavior()
            result.id = $0.1["id"].int32Value
            result.gachaID = $0.1["gachaId"].int32Value
            switch $0.1["gachaBehaviorType"].stringValue {
            case "normal":
                result.gachaBehaviorType = .normal
            case "once_a_day":
                result.gachaBehaviorType = .onceADay
            case "once_a_week":
                result.gachaBehaviorType = .onceAWeek
            case "over_rarity_3_once":
                result.gachaBehaviorType = .overRarity3Once
            case "over_rarity_4_once":
                result.gachaBehaviorType = .overRarity4Once
            default: break
            }
            switch $0.1["costResourceType"].stringValue {
            case "jewel":
                result.costResourceType = .jewel
            case "paid_jewel":
                result.costResourceType = .paidJewel
            case "gacha_ticket":
                result.costResourceType = .gachaTicket
            default: break
            }
            if let value = $0.1["costResourceId"].int32 { result.costResourceID = value }
            if let value = $0.1["gachaBehaviorType"].string { result.typeName = value }
            if let value = $0.1["costResourceType"].string { result.costResourceTypeName = value }
            result.costResourceQuantity = $0.1["costResourceQuantity"].int32Value
            result.spinCount = $0.1["spinCount"].int32Value
            if let limit = $0.1["executeLimit"].int32 { result.executeLimit = limit }
            if let value = $0.1["groupId"].int32 { result.groupID = value }
            result.priority = $0.1["priority"].int32Value
            switch $0.1["resourceCategory"].stringValue {
            case "free_resource":
                result.resourceCategory = .freeResource
            case "consume_resource":
                result.resourceCategory = .consumeResource
            default: break
            }
            switch $0.1["gachaSpinnableType"].stringValue {
            case "any":
                result.gachaSpinnableType = .any
            case "colorful_pass":
                result.gachaSpinnableType = .colorfulPass
            default: break
            }
            return result
        }
        gacha.gachaPickups = gachaJSON["gachaPickups"].map {
            var result = _GachaPickup()
            result.id = $0.1["id"].int32Value
            result.gachaID = $0.1["gachaId"].int32Value
            result.cardID = $0.1["cardId"].int32Value
            switch $0.1["gachaPickupType"] {
            case "normal":
                result.gachaPickupType = .normal
            default: break
            }
            return result
        }
        gacha.gachaInformation = .with {
            $0.gachaID = gachaJSON["gachaInformation"]["gachaId"].int32 ?? gacha.id
            if let value = gachaJSON["gachaInformation"]["summary"].string { $0.summary = value }
            if let value = gachaJSON["gachaInformation"]["description"].string { $0.description_p = value }
        }
        result.append(gacha)
    }
    return result
}
