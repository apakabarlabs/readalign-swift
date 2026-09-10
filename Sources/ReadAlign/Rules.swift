import Foundation
import SwiftEmbed

public struct Rules: Codable, Sendable {
    public let matchThreshold: Double
    public let joinFloor: Double
    public let gapPenalty: Double
    public let mismatchPenalty: Double
    public let roomEnough: TimeInterval
    public let englishVowels: String
    public let foldedLetters: [String: String]

    enum CodingKeys: String, CodingKey {
        case matchThreshold = "match_threshold"
        case joinFloor = "join_floor"
        case gapPenalty = "gap_penalty"
        case mismatchPenalty = "mismatch_penalty"
        case roomEnough = "room_enough"
        case englishVowels = "english_vowels"
        case foldedLetters = "folded_letters"
    }

    public static let shared: Rules = Embedded.getYAML(Bundle.module, path: "rules.yaml")
}
