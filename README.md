[![Tests](https://github.com/apakabarlabs/readalign-swift/actions/workflows/tests.yml/badge.svg)](https://github.com/apakabarlabs/readalign-swift/actions/workflows/tests.yml)
# readalign-swift

Lines a speech recogniser's output up against the text that was read, and says when each word of that text was spoken.

This is not transcription. The words are known in advance; the recogniser is only asked where they are, and it will get some of them wrong, the more so the further the text is from what it was trained on. So words are matched by how alike they look on paper rather than by equality, and a word left unmatched has its time interpolated from the words around it.

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

The one exception is a recording nothing was heard in: that comes back empty rather than with a span per word, because every span would be a guess dressed as a measurement. Check for it before indexing.

Words go in **as they are printed**, hyphens and elision marks and all. `pair` normalises them itself, and it counts the parts of a hyphenated compound before it does; handing it words already stripped of their hyphens tells it every word prints as one, and a compound heard as three words can then never be matched at all.

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

`pair` takes an optional `equivalent` closure, asked as `(written, heard, the written word before it)`. It is for pairs a particular recogniser reliably gets wrong in a way similarity cannot carry: `heir` and `air` share two letters and would never be offered for comparison otherwise, so the patch that knows better is never asked unless the patch reaches the alignment itself.

The predecessor comes along because such a patch is often confined to one turn of phrase, and only the alignment knows what stands where.

It is asked with either side joined up as well, because a recogniser writes a hyphenated compound as two words and two written words as one, and both are one entry in a patch table. Without the joined-written question a model that runs two words together is unpatchable: `in sense` comes back `incense`, which is what those two words sound like said in a row, and similarity alone will not carry it over the join bar. Narrowing the patch entry to the second word instead does not work, since the one heard word is then spent on it and the first has nothing left to match.

### Other languages

Time is shared out among unmatched words by `SpeechWeighting`. A protocol rather than a function so each language brings its own: syllable counting by vowel groups holds for English and breaks on languages that write vowels differently or not at all.

`EnglishSyllableWeighting` counts vowel groups less a silent final `e`, not dropped after `l`. It is wrong on plenty of words (`fire`, `buried`), which is affordable while it only decides whether `self-substantial` gets four times the airtime of `I`. `EvenWeighting` counts every word as one, for a language whose syllables this package cannot count. Pass your own for anything else — but note that what comes back from it is not trusted: a weight that is not a finite number is read as one, because a comparison against such a value is false whichever way round it is put and it would otherwise travel through into every span.

## How it works

### The alignment

Needleman-Wunsch over the two sequences. Both are in reading order, so the alignment may skip words on either side but never reorder them.

Aligning the whole utterance at once, rather than walking forward and stopping at the first divergence, is what lets a caller be told which words went wrong rather than only where things first went wrong: a word mangled in the middle of a line no longer hides the correct words after it.

Every cell of the table is the best of six moves: the two words straight against each other, a skip on either side, one written word against a run of heard words joined up, two written words against one heard word joined up, and both sides joined at once.

### What each move is worth

| move | worth |
|---|---|
| a straight pair at or above the bar | its similarity, `0.6`–`1.0` |
| a joined pair at or above the join bar | its similarity, `0.9`–`1.0` |
| anything below its bar | `-1.5` |
| skipping one word, either side | `-0.5` |

Two words that are merely not opposites still share letters, so raw similarity would pair anything with anything rather than leave a word unpaired. Below the bar a pairing has to be worth **less than passing both words over**, which is what puts a false start outside the line instead of on top of its first words. That is the whole job of the `-1.5`: it is not a measurement, only a number low enough that two skips at `-0.5` beat it.

Note that the bar is applied twice, and the second time is what decides the answer. The table uses these numbers to pick a path; the walk back then records a match only where the pair actually clears its bar. A path may run diagonally through a pair too unalike to be a match, and nothing is recorded there — which is why the exact size of the mismatch price is invisible in the result, and only its being worse than two skips matters.

### Why the join bar is stricter

Word boundaries are not agreed on: a recogniser hears `self-substantial` as two words and `whatever` as one, and neither is a mistake by the reader. So a word may also be matched against the words next to it on the other side, joined up — but only on a near-exact match.

Loosely, joining swallows the neighbouring word whole: `creatures we` would pass as `creatures`, and a swallowed word is one the reader never has to say. Hence `max(threshold, 0.9)` rather than the ordinary bar.

How many heard words one written word may be spread over comes from print: `swift-footed` is two parts, `world-without-end` three. Anything else may still take a pair, since a recogniser splits a long word wherever it likes.

### Tokens with no letters in them

A numeral, a stray mark, or a token a recogniser emitted for a noise normalises to nothing. Joining onto one is free — it adds nothing to the joined string, so it cannot lower the likeness — and a free join hands that token's whole stretch of the recording to the word beside it. `From 1999 fairest` would give `From` everything up to `fairest`.

Nothing is being joined there in any case: a join moves a boundary between two words, and that side has no word. Such a token is passed over instead, which is what the skip is for.

### Placing the words that were not matched

Matched words keep the times they were heard at. An unmatched run is shared across the gap between its nearest matched neighbours, by speech weight, so a long word does not get the same slice of a pause as `a`.

A run can be left no gap at all. The recogniser writes `your self` as one word, the alignment matches that word to `self`, and `your` is left between two marks that touch. Spread across nothing it comes out with no length, and no instant of the recording falls inside a word of no length: a mark that runs along the line as the recording plays passes straight over it, every time.

Room then comes from the neighbour that was holding it — the one dwelling longest on each of its own syllables. A word the recogniser ran another word into keeps both their sounds and so reads as unnaturally slow; its neighbour on the other side is saying only itself.

The same sharing happens inside a single match when several written words were heard as one: `every where` written down as `everywhere`. Given the whole of it, they would lie on top of one another and the first would have nothing left once the ends are tidied.

### Comparing two words

`normalize` keeps letters only, lowercased. Elision marks and punctuation are exactly what a recogniser drops or invents, so comparing without them compares what was actually said.

`similarity` is edit distance over the longer length: `1` for identical, `0` for nothing in common.

## What is shared with the other ports

Two things live as data rather than as code, so that a port in another language reads them instead of holding its own copy.

`Sources/ReadAlign/Resources/rules.yaml` holds the numbers the alignment is tuned to: the two bars, the price of a gap and of a bad pair, the shortest span a word can be found at, and the letters the English weighting counts as vowels. Changing one of them changes every port, rather than leaving them quietly apart.

The cases live in YAML under `Tests/ReadAlignTests/Resources/`, one file per function, and every port is held to the same ones. What stays in Swift is only the runner.

A case pins what it was written to pin and nothing else: `want` lists spans by word index, with `start` and `end` both optional. Filling the rest in from whatever the code currently returns would record the code's opinion of itself rather than a requirement. What is true of every result — a span for every written word, no span ending before it starts, none of them going backwards — is stated once in the runner instead of being copied into each case. A case that asserts nothing fails, so a mistyped key cannot pass for agreement.

Each case carries a `why`, which is where the reason for it lives.

The corpus is checked by mutation: changing the join bar, the match bar, the skip price, the silent-`e` rule, either empty-token guard, the choice of which neighbour swallowed a run, or the patch mechanism must turn it red. The mismatch price is the one constant it does not hold, and cannot: as described above, its size does not reach the result.

## Install

```swift
.package(url: "https://github.com/apakabarlabs/readalign-swift", from: "0.1.0")
```

The API at 0.1.0 is not settled and may change without a major version, so pin an exact version if that matters to you.

Our own apps take it from the checkout beside them instead, so a change here is in the app on the next build without a hop through a tag:

```swift
.package(path: "../../readalign-swift")
```

## Develop

```bash
make test
make lint
```
