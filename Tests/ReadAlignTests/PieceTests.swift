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

struct JoinCase: Codable, CustomTestStringConvertible {
    let name: String
    let sampleRate: Double
    let pieces: [[Int]]
    let heard: [[HeardWord]]
    let equals: [HeardWord]

    enum CodingKeys: String, CodingKey {
        case name, pieces, heard, equals
        case sampleRate = "sample_rate"
    }

    var testDescription: String { name }

    var ranges: [Range<Int>] { pieces.map { $0[0] ..< $0[1] } }
    var transcripts: [[RecognizedWord]] { heard.map { $0.map(\.recognized) } }
    var reading: [RecognizedWord] { equals.map(\.recognized) }
}

struct JoinRefusalCase: Codable, CustomTestStringConvertible {
    let name: String
    let sampleRate: Double
    let pieces: [[Int]]
    let heard: [[HeardWord]]

    enum CodingKeys: String, CodingKey {
        case name, pieces, heard
        case sampleRate = "sample_rate"
    }

    var testDescription: String { name }

    var ranges: [Range<Int>] { pieces.map { $0[0] ..< $0[1] } }
    var transcripts: [[RecognizedWord]] { heard.map { $0.map(\.recognized) } }
}

struct PieceFile: Codable {
    let pauses: [PauseCase]
    let cuts: [CutCase]
    let joins: [JoinCase]
    let joinRefusals: [JoinRefusalCase]

    enum CodingKeys: String, CodingKey {
        case pauses, cuts, joins
        case joinRefusals = "join_refusals"
    }
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
            #expect(later.lowerBound <= earlier.upperBound, "\(cutCase.name): a gap between pieces")
            #expect(later.lowerBound > earlier.lowerBound, "\(cutCase.name): a piece that goes nowhere")
        }
    }

    @Test(arguments: file.joins)
    func joinsThePiecesIntoTheReadingTheCorpusNames(joinCase: JoinCase) throws {
        let reading = try Pieces.joined(
            joinCase.transcripts,
            at: joinCase.ranges,
            sampleRate: joinCase.sampleRate
        )

        #expect(reading == joinCase.reading, "\(joinCase.name): \(reading)")
    }

    @Test(arguments: file.joinRefusals)
    func refusesAPieceAndItsTranscriptThatDoNotPairOff(refusal: JoinRefusalCase) {
        #expect(throws: PiecesError.self, "\(refusal.name)") {
            try Pieces.joined(
                refusal.transcripts,
                at: refusal.ranges,
                sampleRate: refusal.sampleRate
            )
        }
    }

    private static let sampleRate = 16_000.0
    private static let oneWord = [RecognizedWord(text: "heard", start: 0, end: 1)]

    private static func piece(ofSeconds seconds: Double) -> [Float] {
        [Float](repeating: 0.1, count: Int(seconds * sampleRate))
    }

    @Test
    func asksOnceWhenTheFirstAnswerHasWordsInIt() async {
        let piece = Self.piece(ofSeconds: 10)
        var asked: [Int] = []

        let words = await Pieces.heard(of: piece, sampleRate: Self.sampleRate) { given in
            asked.append(given.count)
            return Self.oneWord
        }

        #expect(words == Self.oneWord)
        #expect(asked == [piece.count])
    }

    @Test
    func asksAgainWithLessOfTheTailUntilSomethingComesBack() async {
        let piece = Self.piece(ofSeconds: 10)
        let speaksAfterThreeTenthsTrim = piece.count - Int(0.3 * Self.sampleRate)
        var asked: [Int] = []

        let words = await Pieces.heard(of: piece, sampleRate: Self.sampleRate) { given in
            asked.append(given.count)
            return given.count <= speaksAfterThreeTenthsTrim ? Self.oneWord : []
        }

        #expect(words == Self.oneWord)
        #expect(asked == [piece.count, piece.count - 1_600, piece.count - 3_200, piece.count - 4_800])
    }

    @Test
    func leavesAPieceTooShortToExpectWordsFromAskedOnlyOnce() async {
        var asked = 0

        let words = await Pieces.heard(of: Self.piece(ofSeconds: 1), sampleRate: Self.sampleRate) { _ in
            asked += 1
            return []
        }

        #expect(words.isEmpty)
        #expect(asked == 1)
    }

    @Test
    func answersNothingWhenNoTrimBringsWordsBack() async {
        var asked = 0

        let words = await Pieces.heard(of: Self.piece(ofSeconds: 10), sampleRate: Self.sampleRate) { _ in
            asked += 1
            return []
        }

        #expect(words.isEmpty)
        #expect(asked == 1 + Rules.shared.askAgainTrims.count)
    }
}
