import Foundation
import SwiftEmbed
import Testing
@testable import ReadAlign

enum Corpus {
    static let tolerance = 0.001

    static func load<T: Decodable>(_ path: String, as type: T.Type = T.self) -> T {
        Embedded.getYAML(Bundle.module, path: path, as: type)
    }
}

struct HeardWord: Codable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    var recognized: RecognizedWord {
        RecognizedWord(text: text, start: start, end: end)
    }
}

struct SpanExpectation: Codable {
    let word: Int
    let start: TimeInterval?
    let end: TimeInterval?
    let startAtLeast: TimeInterval?
    let endAtMost: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case word
        case start
        case end
        case startAtLeast = "start_at_least"
        case endAtMost = "end_at_most"
    }
}

enum WeightingName: String, Codable {
    case english
    case even

    var weighting: any SpeechWeighting {
        switch self {
        case .english: EnglishSyllableWeighting()
        case .even: EvenWeighting()
        }
    }
}

extension WordSpan {
    func check(against expectation: SpanExpectation, in name: String) {
        let subject = "\(name), word \(expectation.word)"
        if let start = expectation.start {
            #expect(abs(self.start - start) < Corpus.tolerance, "\(subject): start")
        }
        if let end = expectation.end {
            #expect(abs(self.end - end) < Corpus.tolerance, "\(subject): end")
        }
        if let floor = expectation.startAtLeast {
            #expect(self.start >= floor - Corpus.tolerance, "\(subject): start at least")
        }
        if let ceiling = expectation.endAtMost {
            #expect(self.end <= ceiling + Corpus.tolerance, "\(subject): end at most")
        }
    }
}

func expectWellFormed(_ spans: [WordSpan], count: Int, in name: String) {
    #expect(spans.count == count, "\(name): one span per word")
    for (index, span) in spans.enumerated() {
        #expect(span.end >= span.start, "\(name): word \(index) ends before it starts")
    }
    for (earlier, later) in zip(spans, spans.dropFirst()) {
        #expect(later.start >= earlier.start - Corpus.tolerance, "\(name): spans go backwards")
    }
}
