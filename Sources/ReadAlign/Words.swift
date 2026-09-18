import Foundation

/// Turning the pieces a recogniser answers in into the words it heard.
///
/// A recogniser answers in tokens, not in words: `▁be`, `aut`, `y's`. Where one word ends
/// and the next begins is the recogniser's convention, not the caller's, and every side
/// that reads the same model has to read that convention the same way — otherwise one
/// returns `beauty's` where another returns `beautys` and a third splits the word in two,
/// and the three cannot be held against each other however alike they heard the sound.
public enum Words {
    /// A token that carries one of these opens a word; they are not part of any word.
    private static let opensAWord: Set<Character> = ["▁", "|", " ", "\t", "\n"]

    /// What the recogniser could not spell at all, which belongs in no word.
    private static let unheard = "<unk>"

    /// The words in a recogniser's tokens, each timed from the first token it opens with
    /// to the last it closes with.
    ///
    /// Marks at either end of a word are left off: a word the model wrote `increase,` is
    /// the word `increase`, and the comma is the model's punctuation rather than anything
    /// it heard. Marks inside a word stay, because `beauty's` and `self-substantial` are
    /// words and `beautys` is not.
    public static func spoken(_ tokens: [RecognizedWord]) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var text = ""
        var start = 0.0
        var end = 0.0

        for token in tokens {
            for character in token.text.replacingOccurrences(of: unheard, with: "") {
                if opensAWord.contains(character) {
                    if !text.isEmpty {
                        words.append(RecognizedWord(text: text, start: start, end: end))
                        text = ""
                    }
                    continue
                }
                if text.isEmpty { start = token.start }
                text.append(character)
                end = token.end
            }
        }
        if !text.isEmpty {
            words.append(RecognizedWord(text: text, start: start, end: end))
        }
        return words.compactMap(trimmed)
    }

    private static func trimmed(_ word: RecognizedWord) -> RecognizedWord? {
        let text = word.text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !text.isEmpty else { return nil }
        return RecognizedWord(text: text, start: word.start, end: word.end)
    }
}
