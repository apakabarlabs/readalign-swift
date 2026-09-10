# Changelog

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
