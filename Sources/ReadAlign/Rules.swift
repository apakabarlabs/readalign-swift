import Foundation
import SwiftEmbed

public struct Rules: Codable, Sendable {
    public let matchThreshold: Double
    public let joinFloor: Double
    public let gapPenalty: Double
    public let mismatchPenalty: Double
    public let roomEnough: TimeInterval
    public let joinSpan: Int
    public let englishVowels: String
    public let silentEnding: String
    public let silentEndingExceptAfter: String
    public let shortestWithASilentEnding: Int
    public let lightestWord: Double
    public let liftedMarksFrom: String
    public let liftedMarksTo: String
    public let foldedLetters: [String: String]

    public let frameSeconds: TimeInterval
    public let roomQuantile: Double
    public let speechAboveRoom: Double
    public let quietestRoom: Double
    public let holdLimit: TimeInterval
    public let speechFromLoudestShare: Double
    public let quietestSpeech: Double

    enum CodingKeys: String, CodingKey {
        case matchThreshold = "match_threshold"
        case joinFloor = "join_floor"
        case gapPenalty = "gap_penalty"
        case mismatchPenalty = "mismatch_penalty"
        case roomEnough = "room_enough"
        case joinSpan = "join_span"
        case englishVowels = "english_vowels"
        case silentEnding = "silent_ending"
        case silentEndingExceptAfter = "silent_ending_except_after"
        case shortestWithASilentEnding = "shortest_with_a_silent_ending"
        case lightestWord = "lightest_word"
        case liftedMarksFrom = "lifted_marks_from"
        case liftedMarksTo = "lifted_marks_to"
        case foldedLetters = "folded_letters"
        case frameSeconds = "frame_seconds"
        case roomQuantile = "room_quantile"
        case speechAboveRoom = "speech_above_room"
        case quietestRoom = "quietest_room"
        case holdLimit = "hold_limit"
        case speechFromLoudestShare = "speech_from_loudest_share"
        case quietestSpeech = "quietest_speech"
    }

    public static let shared: Rules = Embedded.getYAML(Bundle.module, path: "rules.yaml")

    /// The marks are written the way Unicode writes them, so they are read that way.
    private static let hexadecimal = 16

    public func lifts(_ scalar: Unicode.Scalar) -> Bool {
        guard let first = UInt32(liftedMarksFrom, radix: Self.hexadecimal),
              let last = UInt32(liftedMarksTo, radix: Self.hexadecimal) else { return false }
        return (first...last).contains(scalar.value)
    }
}
