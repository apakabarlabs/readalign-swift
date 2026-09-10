import Foundation
import Testing
@testable import ReadAlign

/// A written word and the heard word the matching found for it.
struct FoundPair: Codable {
    let word: Int
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct FillCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let expected: [String]
    let pairs: [FoundPair]
    let duration: TimeInterval
    let weighting: WeightingName?
    let want: [SpanExpectation]?
    let nonOverlapping: Bool?

    enum CodingKeys: String, CodingKey {
        case name, why, expected, pairs, duration, weighting, want
        case nonOverlapping = "non_overlapping"
    }

    var testDescription: String { name }
}

struct FillSection: Codable {
    let section: String
    let cases: [FillCase]
}

struct FillFile: Codable {
    let tests: [FillSection]
}

struct FillTests {
    static let cases: [FillCase] = Corpus.load("fill_tests.yaml", as: FillFile.self)
        .tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func fillsAsTheCorpusSays(fillCase: FillCase) {
        let pairs = fillCase.pairs.reduce(into: [Int: RecognizedWord]()) { result, pair in
            result[pair.word] = RecognizedWord(text: pair.text, start: pair.start, end: pair.end)
        }

        let spans = TranscriptAligner.fill(
            expected: fillCase.expected,
            pairs: pairs,
            duration: fillCase.duration,
            weighting: (fillCase.weighting ?? .english).weighting
        )

        expectWellFormed(spans, count: fillCase.expected.count, in: fillCase.name)
        for expectation in fillCase.want ?? [] {
            spans[expectation.word].check(against: expectation, in: fillCase.name)
        }
        guard fillCase.nonOverlapping == true else { return }
        for (earlier, later) in zip(spans, spans.dropFirst()) {
            #expect(
                later.start >= earlier.end - Corpus.tolerance,
                "\(fillCase.name): two words claim the same instant"
            )
        }
    }
}
