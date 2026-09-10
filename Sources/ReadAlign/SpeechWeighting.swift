public protocol SpeechWeighting: Sendable {
    func weight(of word: String) -> Double
}

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

public struct EvenWeighting: SpeechWeighting {
    public init() {}

    public func weight(of word: String) -> Double { 1 }
}
