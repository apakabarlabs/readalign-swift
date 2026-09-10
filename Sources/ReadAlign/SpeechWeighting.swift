import Foundation

/// How long a word takes to say, relative to its neighbours.
///
/// A protocol rather than a function so each language brings its own: syllable
/// counting by vowel groups holds for English and breaks on languages that write
/// vowels differently or not at all.
public protocol SpeechWeighting: Sendable {
    func weight(of word: String) -> Double
}

/// Vowel groups, minus a silent final "e". Wrong on plenty of words ("fire",
/// "buried"), which is affordable while it only decides whether "self-substantial"
/// gets four times the airtime of "I".
public struct EnglishSyllableWeighting: SpeechWeighting {
    public init() {}

    public func weight(of word: String) -> Double {
        Double(syllableCount(of: word))
    }

    public func syllableCount(of word: String) -> Int {
        let vowels = Set("aeiouy")
        let letters = word.lowercased().filter { $0.isLetter }
        guard !letters.isEmpty else { return 1 }

        var count = 0
        var previousWasVowel = false
        for letter in letters {
            let isVowel = vowels.contains(letter)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if letters.count > 2, letters.hasSuffix("e"), !letters.hasSuffix("le"), count > 1 {
            count -= 1
        }
        return max(count, 1)
    }
}

/// Every word weighs the same. For a language whose syllables this package cannot
/// count, which shares an unmatched run out evenly rather than plausibly.
public struct EvenWeighting: SpeechWeighting {
    public init() {}

    public func weight(of word: String) -> Double { 1 }
}
