import Foundation
import Testing
@testable import ReadAlign

/// A match as the corpus writes it: two half-open ranges, `[lower, upper)`.
struct Pairing: Codable {
    let expected: [Int]
    let heard: [Int]

    func matches(_ match: WordMatch) -> Bool {
        match.expected == expected[0]..<expected[1] && match.heard == heard[0]..<heard[1]
    }

    var described: String { "expected \(expected), heard \(heard)" }
}

struct PairCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let expected: [String]
    let heard: [String]
    let threshold: Double
    let want: [Pairing]?
    let wantAbsent: [Pairing]?

    enum CodingKeys: String, CodingKey {
        case name, why, expected, heard, threshold, want
        case wantAbsent = "want_absent"
    }

    var testDescription: String { name }
}

struct PairSection: Codable {
    let section: String
    let cases: [PairCase]
}

struct PairFile: Codable {
    let tests: [PairSection]
}

struct PairTests {
    static let cases: [PairCase] = Corpus.load("pair_tests.yaml", as: PairFile.self)
        .tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func pairsAsTheCorpusSays(pairCase: PairCase) {
        let matches = TranscriptAligner.pair(
            expected: pairCase.expected,
            heard: pairCase.heard,
            threshold: pairCase.threshold
        )

        for wanted in pairCase.want ?? [] {
            #expect(
                matches.contains(where: wanted.matches),
                "\(pairCase.name): no match with \(wanted.described)"
            )
        }
        for unwanted in pairCase.wantAbsent ?? [] {
            #expect(
                !matches.contains(where: unwanted.matches),
                "\(pairCase.name): matched \(unwanted.described), which hides two mistakes"
            )
        }
    }
}
