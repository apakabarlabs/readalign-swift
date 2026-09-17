import Foundation
import Testing

@testable import ReadAlign

struct PauseCase: Codable, CustomTestStringConvertible {
    let name: String
    let sampleRate: Double
    let waveform: [Stretch]
    let equals: [Int]

    enum CodingKeys: String, CodingKey {
        case name, waveform, equals
        case sampleRate = "sample_rate"
    }

    var testDescription: String { name }

    var samples: [Float] {
        waveform.flatMap { stretch in
            [Float](repeating: stretch.level, count: Int((stretch.seconds * sampleRate).rounded()))
        }
    }
}

struct CutCase: Codable, CustomTestStringConvertible {
    let name: String
    let sampleRate: Double
    let waveform: [Stretch]
    let equals: [[Int]]

    enum CodingKeys: String, CodingKey {
        case name, waveform, equals
        case sampleRate = "sample_rate"
    }

    var testDescription: String { name }

    var samples: [Float] {
        waveform.flatMap { stretch in
            [Float](repeating: stretch.level, count: Int((stretch.seconds * sampleRate).rounded()))
        }
    }

    var pieces: [Range<Int>] { equals.map { $0[0] ..< $0[1] } }
}

struct PieceFile: Codable {
    let pauses: [PauseCase]
    let cuts: [CutCase]
}

struct PieceTests {
    static let file: PieceFile = Corpus.load("piece_tests.yaml", as: PieceFile.self)

    @Test(arguments: file.pauses)
    func findsThePausesTheCorpusNames(pauseCase: PauseCase) {
        let found = Pieces.pauses(in: pauseCase.samples, sampleRate: pauseCase.sampleRate)

        #expect(found == pauseCase.equals, "\(pauseCase.name): \(found)")
    }

    @Test(arguments: file.cuts)
    func cutsWhereTheCorpusSays(cutCase: CutCase) {
        let pieces = Pieces.cuts(in: cutCase.samples, sampleRate: cutCase.sampleRate)

        #expect(pieces == cutCase.pieces, "\(cutCase.name): \(pieces)")
    }

    @Test(arguments: file.cuts)
    func leavesNoSampleOutOfEveryPiece(cutCase: CutCase) {
        let pieces = Pieces.cuts(in: cutCase.samples, sampleRate: cutCase.sampleRate)

        #expect(pieces.first?.lowerBound == 0, "\(cutCase.name): starts at \(pieces.first?.lowerBound ?? -1)")
        #expect(pieces.last?.upperBound == cutCase.samples.count, "\(cutCase.name): ends short")
        for (earlier, later) in zip(pieces, pieces.dropFirst()) {
            // Overlap where a pause allows it, but never a gap: a sample no piece holds is
            // a word no recogniser is ever asked about.
            #expect(later.lowerBound <= earlier.upperBound, "\(cutCase.name): a gap between pieces")
            #expect(later.lowerBound > earlier.lowerBound, "\(cutCase.name): a piece that goes nowhere")
        }
    }
}
