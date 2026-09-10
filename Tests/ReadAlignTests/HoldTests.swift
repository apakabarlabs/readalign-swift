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

struct SpeechLevelCase: Codable, CustomTestStringConvertible {
    let name: String
    let sampleRate: Double
    let waveform: [Stretch]
    let equals: Double?
    let atLeast: Double?

    enum CodingKeys: String, CodingKey {
        case name, waveform, equals
        case sampleRate = "sample_rate"
        case atLeast = "at_least"
    }

    var testDescription: String { name }

    var samples: [Float] {
        waveform.flatMap { stretch in
            [Float](repeating: stretch.level, count: Int((stretch.seconds * sampleRate).rounded()))
        }
    }
}

struct HoldFile: Codable {
    let speechLevel: [SpeechLevelCase]
    let tests: [HoldSection]

    enum CodingKeys: String, CodingKey {
        case tests
        case speechLevel = "speech_level"
    }
}

struct HoldTests {
    static let file: HoldFile = Corpus.load("hold_tests.yaml", as: HoldFile.self)
    static let cases: [HoldCase] = file.tests.flatMap(\.cases)

    @Test(arguments: file.speechLevel)
    func measuresHowLoudlyTheRecordingSpeaks(levelCase: SpeechLevelCase) {
        #expect(levelCase.equals != nil || levelCase.atLeast != nil, "\(levelCase.name): pins nothing")

        let level = SilenceHold.speechLevel(
            of: SilenceHold.energyFrames(of: levelCase.samples, sampleRate: levelCase.sampleRate)
        )

        if let exact = levelCase.equals {
            #expect(abs(level - exact) < Corpus.tolerance, "\(levelCase.name): \(level)")
        }
        if let floor = levelCase.atLeast {
            #expect(level >= floor, "\(levelCase.name): \(level)")
        }
    }

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
