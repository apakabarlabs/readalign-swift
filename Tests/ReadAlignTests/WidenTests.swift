import Foundation
import Testing

@testable import ReadAlign

struct WidenFile: Codable {
    let tests: [HoldSection]
}

struct WidenTests {
    static let cases: [HoldCase] = Corpus.load("widen_tests.yaml", as: WidenFile.self).tests
        .flatMap(\.cases)

    @Test(arguments: cases)
    func widensAsTheCorpusSays(widenCase: HoldCase) {
        #expect(widenCase.assertsSomething, "\(widenCase.name): asserts nothing")

        let widened = SilenceHold.widened(
            widenCase.marks,
            samples: widenCase.samples,
            sampleRate: widenCase.sampleRate,
            limit: widenCase.limit ?? Rules.shared.holdLimit
        )

        expectWellFormed(widened, count: widenCase.spans.count, in: widenCase.name)
        for expectation in widenCase.want ?? [] {
            widened[expectation.word].check(against: expectation, in: widenCase.name)
        }
    }
}
