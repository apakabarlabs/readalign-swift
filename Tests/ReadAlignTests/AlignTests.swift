import Foundation
import Testing
@testable import ReadAlign

struct AlignCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let expected: [String]
    let heard: [HeardWord]
    let duration: TimeInterval
    let weighting: WeightingName?
    let want: [SpanExpectation]?
    let strictlyIncreasing: [Int]?
    let wantEmpty: Bool?

    enum CodingKeys: String, CodingKey {
        case name, why, expected, heard, duration, weighting, want
        case strictlyIncreasing = "strictly_increasing"
        case wantEmpty = "want_empty"
    }

    var testDescription: String { name }

    var assertsSomething: Bool {
        wantEmpty == true || !(want ?? []).isEmpty || strictlyIncreasing != nil
    }
}

struct AlignSection: Codable {
    let section: String
    let cases: [AlignCase]
}

struct AlignFile: Codable {
    let tests: [AlignSection]
}

struct AlignTests {
    static let cases: [AlignCase] = Corpus.load("align_tests.yaml", as: AlignFile.self)
        .tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func alignsAsTheCorpusSays(alignmentCase: AlignCase) {
        #expect(alignmentCase.assertsSomething, "\(alignmentCase.name): asserts nothing")

        let spans = TranscriptAligner.align(
            expected: alignmentCase.expected,
            heard: alignmentCase.heard.map(\.recognized),
            duration: alignmentCase.duration,
            weighting: (alignmentCase.weighting ?? .english).weighting
        )

        if alignmentCase.wantEmpty == true {
            #expect(spans.isEmpty, "\(alignmentCase.name): nothing rather than a guess")
            return
        }

        expectWellFormed(spans, count: alignmentCase.expected.count, in: alignmentCase.name)
        for expectation in alignmentCase.want ?? [] {
            spans[expectation.word].check(against: expectation, in: alignmentCase.name)
        }
        for index in (alignmentCase.strictlyIncreasing.map { $0[0]..<($0[1] - 1) } ?? 0..<0) {
            #expect(
                spans[index + 1].start > spans[index].start,
                "\(alignmentCase.name): words \(index) and \(index + 1) land on one instant"
            )
        }
    }
}
