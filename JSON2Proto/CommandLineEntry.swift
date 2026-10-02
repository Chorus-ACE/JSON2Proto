//
//  CommandLineEntry.swift
//  JSON2Proto
//
//  Created by memz233 on 8/20/26.
//

import Foundation
import SwiftProtobuf
import ArgumentParser

@main
struct CommandLineEntry: AsyncParsableCommand {
    @Argument private var outputFolder: String
    @Option(help: "Read JSON from <folder>/<jp|en|tc|cn|kr>/<table>.json instead of GitHub.")
    private var inputFolder: String?
    mutating func run() async throws {
        let outputURL = URL(filePath: outputFolder)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let source = MasterDataSource(inputFolder: inputFolder.map { URL(filePath: $0) })
        
        try await convertGachaList(to: outputURL.appending(path: "gacha.proto"), source: source)
        try await convertCharacterList(to: outputURL.appending(path: "character.proto"), source: source)
        try await convertEventList(to: outputURL.appending(path: "event.proto"), source: source)
        try await convertCardList(to: outputURL.appending(path: "card.proto"), source: source)
    }
}
