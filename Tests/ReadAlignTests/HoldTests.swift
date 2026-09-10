import Foundation
import Testing
@testable import ReadAlign

struct Stretch: Codable {
    let level: Float
    let seconds: Double
}

struct Mark: Codable {
    let start: TimeInterval
    let end: TimeInterval
}

struct HoldCase: Codable, CustomTestStringConvertible {
    let name: String
    let why: String?
    let sampleRate: Double
    let limit: TimeInterval?
    let waveform: [Stretch]
    let spans: [Mark]
    let want: [SpanExpectation]?

    enum CodingKeys: String, CodingKey {
        case name, why, limit, waveform, spans, want
        case sampleRate = "sample_rate"
    }

    var testDescription: String { name }

    var assertsSomething: Bool { !(want ?? []).isEmpty }

    var samples: [Float] {
        waveform.flatMap { stretch in
            [Float](repeating: stretch.level, count: Int((stretch.seconds * sampleRate).rounded()))
        }
    }

    var marks: [WordSpan] {
        spans.map { WordSpan(start: $0.start, end: $0.end) }
    }
}

struct HoldSection: Codable {
    let section: String
    let cases: [HoldCase]
}

struct HoldFile: Codable {
    let tests: [HoldSection]
}

struct HoldTests {
    static let cases: [HoldCase] = Corpus.load("hold_tests.yaml", as: HoldFile.self)
        .tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func holdsAsTheCorpusSays(holdCase: HoldCase) {
        #expect(holdCase.assertsSomething, "\(holdCase.name): asserts nothing")

        let held = SilenceHold.held(
            holdCase.marks,
            samples: holdCase.samples,
            sampleRate: holdCase.sampleRate,
            limit: holdCase.limit ?? Rules.shared.holdLimit
        )

        expectWellFormed(held, count: holdCase.spans.count, in: holdCase.name)
        for expectation in holdCase.want ?? [] {
            held[expectation.word].check(against: expectation, in: holdCase.name)
        }
    }
}
