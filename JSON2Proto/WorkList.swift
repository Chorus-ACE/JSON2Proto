//
//  WorkList.swift
//  JSON2Proto
//
//  Created by memz233 on 8/20/26.
//

import Foundation
import SwiftyJSON
import SwiftProtobuf

func convertGachaList(to url: URL) async throws {
    var gachaList = _GachaList()
    
    let (jpData, _) = try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/Sekai-World/sekai-master-db-diff/refs/heads/main/gachas.json")!)
    let (enData, _) = try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/Sekai-World/sekai-master-db-en-diff/refs/heads/main/gachas.json")!)
    let (tcData, _) = try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/Sekai-World/sekai-master-db-tc-diff/refs/heads/main/gachas.json")!)
    let (cnData, _) = try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/Sekai-World/sekai-master-db-cn-diff/refs/heads/main/gachas.json")!)
    let (krData, _) = try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/Sekai-World/sekai-master-db-kr-diff/refs/heads/main/gachas.json")!)
    
    gachaList.jp = try convertGachaArray(data: jpData)
    gachaList.en = try convertGachaArray(data: enData)
    gachaList.tc = try convertGachaArray(data: tcData)
    gachaList.cn = try convertGachaArray(data: cnData)
    gachaList.kr = try convertGachaArray(data: krData)
    
    try gachaList.serializedData().write(to: url)
}

func convertGachaArray(data: Data) throws -> [_Gacha] {
    let json = try JSON(data: data)
    
    var result: [_Gacha] = []
    result.reserveCapacity(json.count)
    for (_, gachaJSON) in json {
        var gacha = _Gacha()
        gacha.id = gachaJSON["id"].int32Value
        switch gachaJSON["gachaType"].stringValue {
        case "normal":
            gacha.gachaType = .normal
        case "ceil":
            gacha.gachaType = .ceil
        case "gift":
            gacha.gachaType = .gift
        case "beginner":
            gacha.gachaType = .beginner
        default: break
        }
        gacha.name = gachaJSON["name"].stringValue
        gacha.seq = gachaJSON["seq"].int32Value
        gacha.assetBundleName = gachaJSON["assetbundleName"].stringValue
        gacha.gachaCardRarityRateGroupID = gachaJSON["gachaCardRarityRateGroupId"].int32Value
        gacha.startAt = gachaJSON["startAt"].int64Value
        gacha.endAt = gachaJSON["endAt"].int64Value
        gacha.isShowPeriod = gachaJSON["isShowPeriod"].boolValue
        gacha.gachaCeilItemID = gachaJSON["gachaCeilItemId"].int32Value
        gacha.wishSelectCount = gachaJSON["wishSelectCount"].int32Value
        gacha.wishFixedSelectCount = gachaJSON["wishFixedSelectCount"].int32Value
        gacha.wishLimitedSelectCount = gachaJSON["wishLimitedSelectCount"].int32Value
        gacha.isSelectCharacter = gachaJSON["isSelectCharacter"].boolValue
        gacha.gachaCardRarityRates = gachaJSON["gachaCardRarityRates"].map {
            var result = _GachaCardRarityRate()
            result.id = $0.1["id"].int32Value
            result.groupID = $0.1["groupId"].int32Value
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
            return result
        }
        gacha.gachaDetails = gachaJSON["gachaDetails"].map {
            var result = _GachaDetail()
            result.id = $0.1["id"].int32Value
            result.gachaID = $0.1["gachaId"].int32Value
            result.cardID = $0.1["cardId"].int32Value
            result.weight = $0.1["weight"].int32Value
            result.isWish = $0.1["isWish"].boolValue
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
            result.costResourceID = $0.1["costResourceId"].int32Value
            result.costResourceQuantity = $0.1["costResourceQuantity"].int32Value
            result.spinCount = $0.1["spinCount"].int32Value
            result.groupID = $0.1["groupId"].int32Value
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
            $0.gachaID = gachaJSON["gachaInformation"]["gachaId"].int32Value
            $0.summary = gachaJSON["gachaInformation"]["gachaId"].stringValue
            $0.description_p = gachaJSON["gachaInformation"]["description"].stringValue
        }
        result.append(gacha)
    }
    return result
}
