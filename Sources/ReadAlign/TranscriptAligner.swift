import Foundation

public struct RecognizedWord: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct WordSpan: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

public struct WordMatch: Sendable, Equatable {
    public let expected: Range<Int>
    public let heard: Range<Int>

    public init(expected: Range<Int>, heard: Range<Int>) {
        self.expected = expected
        self.heard = heard
    }
}

public enum TranscriptAligner {
    public static let matchThreshold = Rules.shared.matchThreshold

    public static func align(
        expected: [String],
        heard: [RecognizedWord],
        duration: TimeInterval,
        weighting: any SpeechWeighting = EnglishSyllableWeighting(),
        equivalent: ((String, String, String?) -> Bool)? = nil
    ) -> [WordSpan] {
        guard !expected.isEmpty else { return [] }
        guard !heard.isEmpty else { return [] }

        let pairs = match(
            expected: expected,
            heard: heard,
            weighting: weighting,
            equivalent: equivalent
        )
        return fill(expected: expected, pairs: pairs, duration: duration, weighting: weighting)
    }

    static func match(
        expected: [String],
        heard: [RecognizedWord],
        weighting: any SpeechWeighting = EnglishSyllableWeighting(),
        equivalent: ((String, String, String?) -> Bool)? = nil
    ) -> [Int: RecognizedWord] {
        let matches = pair(
            expected: expected,
            heard: heard.map(\.text),
            threshold: matchThreshold,
            equivalent: equivalent
        )
        return matches.reduce(into: [Int: RecognizedWord]()) { result, match in
            let start = heard[match.heard.lowerBound].start
            let end = heard[match.heard.upperBound - 1].end
            guard match.expected.count > 1 else {
                result[match.expected.lowerBound] = RecognizedWord(
                    text: heard[match.heard.lowerBound].text,
                    start: start,
                    end: end
                )
                return
            }
            let weights = match.expected.map { speechWeight(of: expected[$0], using: weighting) }
            let total = weights.reduce(0, +)
            var cursor = start
            for (index, weight) in zip(match.expected, weights) {
                let length = (end - start) * weight / total
                result[index] = RecognizedWord(
                    text: heard[match.heard.lowerBound].text,
                    start: cursor,
                    end: cursor + length
                )
                cursor += length
            }
        }
    }

    public static func pair(
        expected: [String],
        heard: [String],
        threshold: Double,
        equivalent: ((String, String, String?) -> Bool)? = nil
    ) -> [WordMatch] {
        guard !expected.isEmpty, !heard.isEmpty else { return [] }
        let alignment = Alignment(
            expected: expected.map(normalize),
            heard: heard.map(normalize),
            threshold: threshold,
            equivalent: equivalent,
            printedParts: expected.map(printedParts)
        )
        return alignment.matches(in: alignment.scores())
    }

    static func fill(
        expected: [String],
        pairs: [Int: RecognizedWord],
        duration: TimeInterval,
        weighting: any SpeechWeighting = EnglishSyllableWeighting()
    ) -> [WordSpan] {
        var timings: [WordSpan?] = Array(repeating: nil, count: expected.count)
        for (index, word) in pairs {
            timings[index] = WordSpan(start: word.start, end: word.end)
        }

        var index = 0
        while index < timings.count {
            guard timings[index] == nil else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd < timings.count, timings[runEnd] == nil {
                runEnd += 1
            }
            var first = index
            var last = runEnd
            var runStart = index > 0 ? timings[index - 1]?.end ?? 0 : 0
            var runFinish = runEnd < timings.count ? timings[runEnd]?.start ?? duration : duration

            if runFinish - runStart < roomEnough * Double(runEnd - index),
                let host = swallower(
                    of: index..<runEnd,
                    in: timings,
                    expected: expected,
                    weighting: weighting
                ),
                let stretch = timings[host]
            {
                if host < index {
                    first = host
                    runStart = stretch.start
                } else {
                    last = host + 1
                    runFinish = stretch.end
                }
            }

            let weights = (first..<last).map { speechWeight(of: expected[$0], using: weighting) }
            let total = weights.reduce(0, +)
            var cursor = runStart
            for (offset, weight) in zip(first..<last, weights) {
                let length = max(runFinish - runStart, 0) * weight / total
                timings[offset] = WordSpan(start: cursor, end: cursor + length)
                cursor += length
            }
            index = runEnd
        }
        return timings.compactMap(\.self)
    }

    private static let roomEnough = Rules.shared.roomEnough

    private static func swallower(
        of run: Range<Int>,
        in timings: [WordSpan?],
        expected: [String],
        weighting: any SpeechWeighting
    ) -> Int? {
        func perSyllable(_ index: Int) -> Double? {
            guard timings.indices.contains(index), let timing = timings[index] else { return nil }
            return (timing.end - timing.start) / speechWeight(of: expected[index], using: weighting)
        }
        let before = perSyllable(run.lowerBound - 1)
        let after = perSyllable(run.upperBound)
        switch (before, after) {
        case let (before?, after?): return after >= before ? run.upperBound : run.lowerBound - 1
        case (_?, nil): return run.lowerBound - 1
        case (nil, _?): return run.upperBound
        case (nil, nil): return nil
        }
    }

    private static func speechWeight(
        of word: String,
        using weighting: any SpeechWeighting
    ) -> Double {
        let weight = weighting.weight(of: word)
        let lightest = Rules.shared.lightestWord
        return weight.isFinite ? max(weight, lightest) : lightest
    }

    static func letters(_ word: String) -> [String] {
        clusters(lowercased(word.precomposedStringWithCanonicalMapping)).filter(isLetter)
    }

    static func clusters(_ word: String) -> [String] {
        var found: [String] = []
        var letter = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            if let last = letter.last, !joinsOn(scalar, after: last) {
                found.append(String(letter))
                letter = String.UnicodeScalarView()
            }
            letter.append(scalar)
        }
        if !letter.isEmpty { found.append(String(letter)) }
        return found
    }

    private static func joinsOn(_ scalar: Unicode.Scalar, after last: Unicode.Scalar) -> Bool {
        if isMark(scalar) || scalar == zeroWidthNonJoiner || scalar == zeroWidthJoiner {
            return true
        }
        return Rules.shared.joins(last) && scalar.properties.isAlphabetic
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        [.nonspacingMark, .enclosingMark, .spacingMark].contains(scalar.properties.generalCategory)
    }

    private static let zeroWidthNonJoiner: Unicode.Scalar = "\u{200C}"
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"

    private static func lowercased(_ word: String) -> String {
        let characters = Array(word)
        func isCased(_ index: Int) -> Bool {
            guard characters.indices.contains(index) else { return false }
            return characters[index].unicodeScalars.contains(where: \.properties.isCased)
        }
        return characters.indices
            .map { index -> String in
                guard characters[index] == "\u{03A3}" else { return characters[index].lowercased() }
                return isCased(index - 1) && !isCased(index + 1) ? "\u{03C2}" : "\u{03C3}"
            }
            .joined()
    }

    public static func normalize(_ word: String) -> String {
        letters(word).joined()
    }

    private static func isLetter(_ cluster: String) -> Bool {
        guard let category = cluster.unicodeScalars.first?.properties.generalCategory else {
            return false
        }
        return [
            .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .letterNumber
        ].contains(category)
    }

    static func printedParts(_ word: String) -> Int {
        max(word.split(separator: "-").count, 1)
    }

    public static func fold(_ word: String) -> String {
        let scalars = word.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !Rules.shared.lifts($0) }
        let lifted = String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
        return
            lifted
            .map { character in Rules.shared.foldedLetters[String(character)] ?? String(character) }
            .joined()
    }

    static func similarity(_ left: String, _ right: String) -> Double {
        let written = fold(left)
        let said = fold(right)
        if written == said { return 1 }
        if written.isEmpty || said.isEmpty { return 0 }
        let writtenLetters = clusters(written)
        let saidLetters = clusters(said)
        let distance = editDistance(writtenLetters, saidLetters)
        return 1 - Double(distance) / Double(max(writtenLetters.count, saidLetters.count))
    }

    private static func editDistance(_ left: [String], _ right: [String]) -> Int {
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for row in 1...left.count {
            current[0] = row
            for column in 1...right.count {
                let substitution =
                    previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1)
                current[column] = min(substitution, previous[column] + 1, current[column - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
