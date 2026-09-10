import Foundation
import Testing
@testable import ReadAlign

struct NormalizeCase: Codable, CustomTestStringConvertible {
    let word: String
    let want: String

    var testDescription: String { "\(word) -> \(want)" }
}

struct SimilarityCase: Codable, CustomTestStringConvertible {
    let left: String
    let right: String
    let equals: Double?
    let atLeast: Double?
    let atMost: Double?

    enum CodingKeys: String, CodingKey {
        case left, right, equals
        case atLeast = "at_least"
        case atMost = "at_most"
    }

    var testDescription: String { "\(left) against \(right)" }
}

struct SyllableCase: Codable, CustomTestStringConvertible {
    let word: String
    let count: Int?
    let atLeast: Int?

    enum CodingKeys: String, CodingKey {
        case word, count
        case atLeast = "at_least"
    }

    var testDescription: String { word }
}

struct PrintedPartsCase: Codable, CustomTestStringConvertible {
    let word: String
    let parts: Int

    var testDescription: String { "\(word) -> \(parts)" }
}

struct WordFile: Codable {
    let printedParts: [PrintedPartsCase]
    let normalize: [NormalizeCase]
    let similarity: [SimilarityCase]
    let englishSyllables: [SyllableCase]

    enum CodingKeys: String, CodingKey {
        case normalize, similarity
        case printedParts = "printed_parts"
        case englishSyllables = "english_syllables"
    }
}

struct WordTests {
    static let file: WordFile = Corpus.load("word_tests.yaml", as: WordFile.self)

    @Test(arguments: file.printedParts)
    func countsPrintedPartsAsTheCorpusSays(partsCase: PrintedPartsCase) {
        #expect(TranscriptAligner.printedParts(partsCase.word) == partsCase.parts, "\(partsCase.word)")
    }

    @Test(arguments: file.normalize)
    func normalizesAsTheCorpusSays(normalizeCase: NormalizeCase) {
        #expect(TranscriptAligner.normalize(normalizeCase.word) == normalizeCase.want)
    }

    @Test(arguments: file.similarity)
    func scoresLikenessAsTheCorpusSays(similarityCase: SimilarityCase) {
        let score = TranscriptAligner.similarity(similarityCase.left, similarityCase.right)
        if let exact = similarityCase.equals {
            #expect(abs(score - exact) < Corpus.tolerance)
        }
        if let floor = similarityCase.atLeast {
            #expect(score >= floor)
        }
        if let ceiling = similarityCase.atMost {
            #expect(score <= ceiling)
        }
    }

    @Test(arguments: file.englishSyllables)
    func countsEnglishSyllablesAsTheCorpusSays(syllableCase: SyllableCase) {
        let counted = EnglishSyllableWeighting().syllableCount(of: syllableCase.word)
        if let exact = syllableCase.count {
            #expect(counted == exact, "\(syllableCase.word)")
        }
        if let floor = syllableCase.atLeast {
            #expect(counted >= floor, "\(syllableCase.word)")
        }
    }
}
