import Foundation
import SwiftEmbed
import Testing
@testable import ReadAlign

/// The cases live in YAML so that every port of this package is held to the same
/// ones. What stays here is only what runs them.
enum Corpus {
    /// Times are written out to the millisecond, so anything closer than that is the
    /// same instant said two ways.
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

/// What a case says about one word's span. Every field is optional: a case pins
/// what it was written to pin, and filling the rest in from whatever the code
/// currently returns would only record the code's opinion of itself.
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

/// Named weightings, so a case can ask for one without the corpus knowing Swift.
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
        let where_ = "\(name), word \(expectation.word)"
        if let start = expectation.start {
            #expect(abs(self.start - start) < Corpus.tolerance, "\(where_): start")
        }
        if let end = expectation.end {
            #expect(abs(self.end - end) < Corpus.tolerance, "\(where_): end")
        }
        if let floor = expectation.startAtLeast {
            #expect(self.start >= floor - Corpus.tolerance, "\(where_): start at least")
        }
        if let ceiling = expectation.endAtMost {
            #expect(self.end <= ceiling + Corpus.tolerance, "\(where_): end at most")
        }
    }
}

/// True of every result, whatever the case was written to show: a span for every
/// written word, no span ending before it starts, and none of them going backwards.
/// Stated once here rather than repeated in each case.
func expectWellFormed(_ spans: [WordSpan], count: Int, in name: String) {
    #expect(spans.count == count, "\(name): one span per word")
    for (index, span) in spans.enumerated() {
        #expect(span.end >= span.start, "\(name): word \(index) ends before it starts")
    }
    for (earlier, later) in zip(spans, spans.dropFirst()) {
        #expect(later.start >= earlier.start - Corpus.tolerance, "\(name): spans go backwards")
    }
}
