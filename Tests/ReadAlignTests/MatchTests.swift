import Foundation
import Testing
@testable import ReadAlign

struct MatchCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let expected: [String]
    let heard: [HeardWord]
    let weighting: WeightingName?
    let want: [SpanExpectation]?
    let contiguous: [Int]?

    var testDescription: String { name }

    var assertsSomething: Bool {
        !(want ?? []).isEmpty || contiguous != nil
    }
}

struct MatchSection: Codable {
    let section: String
    let cases: [MatchCase]
}

struct MatchFile: Codable {
    let tests: [MatchSection]
}

struct MatchTests {
    static let cases: [MatchCase] = Corpus.load("match_tests.yaml", as: MatchFile.self)
        .tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func placesWordsAsTheCorpusSays(matchCase: MatchCase) throws {
        #expect(matchCase.assertsSomething, "\(matchCase.name): asserts nothing")

        let placed = TranscriptAligner.match(
            expected: matchCase.expected,
            heard: matchCase.heard.map(\.recognized),
            weighting: (matchCase.weighting ?? .english).weighting
        )

        for expectation in matchCase.want ?? [] {
            let word = try #require(
                placed[expectation.word],
                "\(matchCase.name): word \(expectation.word) was not placed at all"
            )
            WordSpan(start: word.start, end: word.end)
                .check(against: expectation, in: matchCase.name)
            #expect(
                word.end > word.start,
                "\(matchCase.name): word \(expectation.word) has no length"
            )
        }

        for index in (matchCase.contiguous.map { $0[0]..<($0[1] - 1) } ?? 0..<0) {
            let earlier = try #require(placed[index])
            let later = try #require(placed[index + 1])
            #expect(
                abs(later.start - earlier.end) < Corpus.tolerance,
                "\(matchCase.name): words \(index) and \(index + 1) do not touch"
            )
        }
    }
}
