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

/// A pair the caller vouches for, whatever it looks like. `after` narrows the patch
/// to one turn of phrase: the written word that has to stand before the pair.
struct EquivalentEntry: Codable {
    let written: String
    let heard: String
    let after: String?
}

struct PairCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let expected: [String]
    let heard: [String]
    let threshold: Double
    let equivalent: [EquivalentEntry]?
    let want: [Pairing]?
    let wantAbsent: [Pairing]?

    enum CodingKeys: String, CodingKey {
        case name, why, expected, heard, threshold, equivalent, want
        case wantAbsent = "want_absent"
    }

    var testDescription: String { name }

    /// A case that asserts nothing passes for the wrong reason, and a mistyped key
    /// decodes to nothing rather than to an error.
    var assertsSomething: Bool {
        !(want ?? []).isEmpty || !(wantAbsent ?? []).isEmpty
    }

    var patch: ((String, String, String?) -> Bool)? {
        guard let entries = equivalent else { return nil }
        return { written, heard, after in
            entries.contains { entry in
                entry.written == written
                    && entry.heard == heard
                    && (entry.after == nil || entry.after == after)
            }
        }
    }
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
        #expect(pairCase.assertsSomething, "\(pairCase.name): asserts nothing")

        let matches = TranscriptAligner.pair(
            expected: pairCase.expected,
            heard: pairCase.heard,
            threshold: pairCase.threshold,
            equivalent: pairCase.patch
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
