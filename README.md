[![Tests](https://github.com/apakabarlabs/readalign-swift/actions/workflows/tests.yml/badge.svg)](https://github.com/apakabarlabs/readalign-swift/actions/workflows/tests.yml)
# readalign-swift

Lines a speech recogniser's output up against the text that was read, and says when each word of that text was spoken.

This is not transcription. The words are known in advance; the recogniser is only asked where they are, and it will get some of them wrong. So words are matched by how alike they look on paper rather than by equality, and a word left unmatched has its time interpolated from the words around it.

## What it handles

- **A misheard word.** `stowage` comes back as `stoage`, `harbour` as `harbor`. Matched on similarity, so the word keeps its own time.
- **A word boundary in the wrong place.** `shouldst owe` comes back as `should stow`: the same sound, the gap moved one consonant cluster. Matched as a pair, on a stricter bar than a single word.
- **One written word heard as several.** A hyphenated compound says how many parts it has, and the whole of what was heard is timed across all of them.
- **Several written words heard as one.** `every where` comes back as `everywhere`; the stretch is shared out between them by speech weight rather than given to both.
- **A word nobody said.** A gap costs less than a bad pair, so a false start or an `um` is passed over instead of being pushed into a neighbouring word.
- **A run of words the recogniser dropped.** Their time is shared across the gap they left, by speech weight, so a long word does not get the same slice of a pause as `a`. If the gap is nothing at all, room comes from the neighbour that swallowed them.

## Use

```swift
import ReadAlign

let spans = TranscriptAligner.align(
    expected: ["From", "fairest", "creatures", "we", "desire", "increase"],
    heard: [
        RecognizedWord(text: "from", start: 0.00, end: 0.32),
        RecognizedWord(text: "farest", start: 0.32, end: 0.81),
        RecognizedWord(text: "creatures", start: 0.81, end: 1.44),
        RecognizedWord(text: "we", start: 1.44, end: 1.60),
        RecognizedWord(text: "desire", start: 1.60, end: 2.08),
        RecognizedWord(text: "increase", start: 2.08, end: 2.72)
    ],
    duration: 3.0
)
// spans[1] == WordSpan(start: 0.32, end: 0.81)
```

One span per expected word, in reading order. What a word is on the page — which line it sits in, which of its letters get painted — stays with the caller.

To ask only which word came back as which, without times:

```swift
let matches = TranscriptAligner.pair(
    expected: ["hearts", "shouldst", "owe"],
    heard: ["hearts", "should", "stow"],
    threshold: 0.6
)
// the pair whose boundary moved comes back as one match: expected 1..<3, heard 1..<3
```

### Recogniser patches

`pair` takes an optional `equivalent` closure, asked as `(written, heard, the written word before it)`. It is for pairs a particular recogniser reliably gets wrong in a way similarity cannot carry: `heir` and `air` share two letters and would never be offered for comparison otherwise. The predecessor comes along because such a patch is often confined to one turn of phrase.

### Other languages

Time is shared out among unmatched words by `SpeechWeighting`. `EnglishSyllableWeighting` counts vowel groups, which holds for English and breaks on languages that write vowels differently or not at all; `EvenWeighting` counts every word as one. Pass your own for anything else.

## Install

```swift
.package(url: "https://github.com/apakabarlabs/readalign-swift", from: "0.1.0")
```

## The case corpus

The cases live in YAML under `Tests/ReadAlignTests/Resources/`, one file per function, and every port of this package is held to the same ones. What stays in Swift is only the runner.

A case pins what it was written to pin and nothing else: `want` lists spans by word index, with `start` and `end` both optional. Filling the rest in from whatever the code currently returns would record the code's opinion of itself rather than a requirement. What is true of every result — a span for every written word, no span ending before it starts, none of them going backwards — is stated once in the runner instead of being copied into each case.

## Develop

```bash
make test
make lint
```
