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
    mutating func run() async throws {
        let outputURL = URL(filePath: outputFolder)
        
        try await convertGachaList(to: outputURL.appending(path: "gacha.proto"))
    }
}
