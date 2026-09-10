# Changelog

## 0.2.0

A Python port of this library now exists, and the two are held to one set of tuned numbers and one set of cases so they cannot come to disagree. Both carry the same major and minor version for that reason.

### Added
- `SilenceHold.held` carries each word's mark into the quiet behind it, and never into the word that follows. A recogniser marks where a word stops being audible, not where the voice has finished with it, so a passage played to the mark stops a hair short of itself. It is the one call that needs the recording.

### Changed
- Likeness is measured with diacritical marks lifted. A recogniser trained on plain Latin returns `casa` for `čaša` and `lodz` for `łódź`, and in a short word two lost marks put it under any usable bar: the word was not found at all, and the stretch it was given ran between its neighbours, so a mark following the reading sat on a word nobody was saying. `normalize` is unchanged, so a reader saying `zamek` for `żamek` is still not credited with it — lifting the marks is for finding where a word is, not for deciding whether it was said.
- The numbers the alignment is tuned to moved out of the source into `rules.yaml`, which every port reads.

### Fixed
- A token with no letters in it — a numeral, a stray mark — was joined onto its neighbour for free, because it adds nothing to the joined string and so cannot lower the likeness. `From 1999 fairest` gave `From` everything up to `fairest`. Such a token is now passed over.
- A weighting answering with something that is not a number travelled through `max` into every span. It is read as one instead.

## 0.1.0

First release. Nothing to migrate from.

### Added

Two calls, for the case where you already hold the text that was read aloud and only want to know where its words fall in the recording.

- `TranscriptAligner.align` takes the words of that text, the words a speech recogniser returned with the start and end it heard each at, and the length of the recording. It returns one start and one end per word of your text, in seconds, in reading order. A recording nothing was heard in returns nothing rather than a span per word.
- `TranscriptAligner.pair` answers the same question without times: which written word came back as which heard word. Its `threshold` is how alike two words must be to count as the same word; its optional `equivalent` lets you vouch for a pair a particular recogniser always gets wrong, such as `heir` heard as `air`.
- `SpeechWeighting`, a protocol with two implementations. It decides how the recording is shared out among words the recogniser did not return at all, so that a long word does not get the same slice of a pause as `a`. `EnglishSyllableWeighting` counts English syllables; `EvenWeighting` gives every word the same share, which is what a language it cannot count should use until someone writes one for it.

The alignment tolerates what recognisers do to a text they were not given: a misspelt word keeps its own time, a word boundary put in the wrong place is matched across both words at once, a hyphenated compound heard as three words is timed across all three, two written words heard as one share the stretch between them, and a word nobody said is passed over instead of being pushed onto a written word.

The inputs and expected results of every case this release is held to are kept as data beside the tests rather than written into them, so that a rewrite of this library in another programming language can be checked against the same cases rather than against a translation of them.

API at 0.1.0 is not yet settled and may change without a major version.
