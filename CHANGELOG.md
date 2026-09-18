# Changelog

## 0.12.0

`least_overlap`, which 0.11.0 added, is gone again. It was measured and cost more than it saved; use 0.10.0 or this, not 0.11.0.

### Removed
- `least_overlap` from `rules.yaml` and `Rules`, and the floor it put under the overlap between two pieces. Two pieces can again meet edge to edge where no pause offers itself to begin the next at.

  What the floor was for is real: pieces that meet exactly share no ground, the join has nothing to settle them by, and a word invented at the edge of one of them stands. Over 154 readings ten are cut that way and every one gains a word on the side that pads its input to a fixed length.

  What it cost is larger. Moving the start of a piece changes the length of what the model is asked, and this model answers a different length with different words: between two of the three sides, 222 differences with no floor, 225 at two seconds, 248 at half a second. The ten invented words went at two seconds and twelve other differences arrived in their place. A seam is not worth paying for with every other piece.

## 0.11.0

`Pieces.cuts` never hands back two pieces that meet edge to edge. Nothing you call changes; where the pieces fall does. **Measured worse than 0.10.0 and undone in 0.12.0.**

### Changed
- The next piece begins one pause earlier than the last ended, as before, and now never less than `least_overlap` earlier. Where no pause offered itself the two pieces met exactly, shared no ground at all, and the join had nothing to settle them by — a recogniser invents a word while it is hearing the last of what it was given, and with nothing in common there was nothing to catch it against. Measured over 154 readings, ten of them were cut that way and every one of those gained a word on the side that pads its input to a fixed length; with the floor the invented word is gone from all ten and two of the readings come back word for word alike with the other side.
- Beginning the next piece earlier can leave more than a piece still to ask, and then there is one more piece than there would have been. The last of them is mostly ground already covered, which the join takes off.

## 0.10.0

Nothing you call has to change. If you turn a recogniser's tokens into words yourself, that is now a call.

### Added
- `Words.spoken` gathers a recogniser's tokens into the words they spell. A recogniser answers in tokens, not in words — `▁be`, `aut`, `y's` — and where one word ends is the model's convention rather than the caller's. Written out by each side, one returns `beauty's` where another returns `beautys` and a third splits the word in two, and the three readings cannot be held against each other however alike they heard the sound. A token opening with `▁`, a space or `|` opens a word; each word is timed from the token it opens with to the one it closes with; marks at either end of a word are the model's punctuation and are left off, while marks inside it stay.

## 0.9.0

`Pieces.joined` drops the second copy of a seam word by the text alone. Nothing you call changes; what comes back does, and `same_moment` is gone from `rules.yaml`.

### Changed
- The overlap is settled by the longest run the two pieces say alike inside it: everything the coming piece says up to the end of that run comes off. Before, a word was a second copy if it was marked within `same_moment` of one already kept and spelled the same. The clock is the one thing two builds of one model do not share: measured on a sonnet, the same word came back 0.20 s apart in two pieces of one recording, just outside the bar, and a different runtime puts it somewhere else again. So one build kept the word twice and another kept it once, from the same recording and the same cut. The words agree where the marks do not.
- The run is looked for anywhere inside the overlap rather than at its edges, because a recogniser drops or invents a word at the edge of what it was given: one piece ended `...by time decease we` where the other heard no `we` at all, and a run pinned to the edges finds nothing and leaves the whole overlap said twice. A run of a single word counts only when it is the whole of what the coming piece says in the overlap.
- Past the run the coming piece is believed and the piece before it is not: they cover the same seconds there, and the one that goes on past them heard them with what follows while the other was hearing the last of what it was given. So a word invented at the edge of a piece now goes rather than standing in the reading.
- A word the reading genuinely says twice at a seam is still kept twice, and pieces that disagree about the overlap still keep what each of them said.

### Removed
- `same_moment` from `rules.yaml` and `Rules`. Nothing reads it now, and a number left behind reads as one the code obeys.

## 0.8.1

### Changed
- `Pieces.heard` takes an `async` closure and is awaited. Every recogniser it is written for answers that way, and a caller that had to bridge the two would be writing the asking again itself, which is the thing this call exists to stop. The other ports are unchanged: their recognisers answer in place.

## 0.8.0

Nothing you call has to change. If you hand a piece of a recording to a speech recogniser, there is a new call to hand it over through.

### Added
- `Pieces.heard(of:sampleRate:asking:)` asks the recogniser through you, and asks again with less of the tail while nothing comes back. Parakeet answers some pieces of ordinary speech with no words at all, and whether it does turns on where the piece starts and how long it is together rather than on the speech in it: the mel statistics are taken over the piece, so its length moves them, and past some edge the decoder predicts blank at every frame. The lengths to take off and the order to try them are `ask_again_trims` in `rules.yaml`, and `shortest_worth_asking_again` is the length below which nothing heard is simply an answer. What comes back this way is missing whatever was said in the trimmed tail, which the overlap with the next piece covers.

## 0.7.0

Nothing you call has to change. If you cut a recording with `Pieces.cuts` and stitched the answers back together yourself, that part is now a call.

### Added
- `Pieces.joined` turns what each piece came back with into one reading, placed in the seconds of the whole recording. The pieces overlap, so a word at a seam arrives twice, and the second copy goes by time and text together, on `same_moment` in `rules.yaml`: how close two marks of one word have to be for the overlap to have said it once. Left to each caller, this is where two sides that cut a reading identically still end up with different transcripts.
- A piece the recogniser had nothing to say about adds nothing, which is an answer rather than a fault. A transcript missing for a piece, or one too many, is refused rather than paired off until the shorter of the two runs out: every word after the missing one would be placed at the wrong moment, and the reading would come back looking whole.

## 0.6.0

Nothing you call has to change. There is a new call for anyone who hands a long recording to a speech recogniser.

### Added
- `Pieces.cuts` says where to cut a recording into the pieces a recogniser is asked one at a time, and `Pieces.pauses` says where it is quiet long enough to cut. A recogniser handed a long reading cuts it into windows of its own, and every runtime cuts differently: one took fifteen-second windows and dropped the last line of a forty-second reading, while another was handed the same reading whole. Cut it here first and every side is asked the same question.
- Four numbers in `rules.yaml` decide it: how long a piece may be, the earliest it may end, how long quiet has to last to count as a pause, and how close two marks of one word have to be for the overlap to say it once.

### Notes
- A reading with hardly any silence in it is cut on length alone. Quiet is measured against the quietest tenth of the recording itself, so where that tenth is already speech, no pause stands out from it.

## 0.5.0

Nothing you call has to change. What comes back changes for Greek words ending in a capital sigma, and for any word whose letters the platform used to cut apart differently from the sibling ports.

### Changed
- Where a word is cut into letters is decided here rather than by the platform. Every platform answers that question, and they answer it differently and at different vintages, which a library claiming that three ports read one word cannot leave to whoever is running it. The marks that write one consonant joined to the next are named in `rules.yaml`, and the letters of eleven writing systems are pinned letter by letter in the cases. A script is added to that list by being shown a case, not by resemblance: several scripts write a mark that looks the same and do not join their consonants with it.

### Fixed
- A sigma ending a Greek word is written its own way, and `lowercased()` writes every sigma the same. A word ending in a capital sigma therefore came back spelled a way the other two libraries would not find it by, and read aloud it was simply not there.

## 0.4.0

Nothing you call has to change. A token that is only a mark now normalises to nothing, as the README always said it did, so what comes back changes where such a token appears.

### Fixed
- A mark that is only ever written above or beside a letter is no longer a word in its own right. A Devanagari visarga standing alone used to normalise to itself and so be joined onto the word beside it, taking that word's stretch of the recording with it; it is now passed over, which is what a stray mark has always been documented to do. The letters of a word are unaffected: a mark attached to its letter is part of that letter as before.
- A `folded_letters` entry longer than one character is honoured whole rather than cut to its first character. Every entry in `rules.yaml`, the file of numbers and letters the ports share, is one character today, so nothing changes yet; adding a two-letter fold would otherwise have produced two answers across the ports from a file whose purpose is that they produce one.

### Added
- A Kotlin port, [readalign-kotlin](https://github.com/apakabarlabs/readalign-kotlin). The shared cases now pin where a language's letters are cut apart, which is not something a port may answer for itself: a word carrying a zero-width joiner and a word carrying a spacing mark each have a case of their own.

## 0.3.0

Nothing you call has to change. What comes back changes wherever accents are involved, on either side — see Fixed.

### Added
- `align` takes the optional `equivalent` closure `pair` already had: it is asked the written word, the heard word, and the written word before it — `nil` at the start of the text — and answers `true` when those two are the same word however unlike they are spelled. Left out, nothing is vouched for and similarity alone decides, as before. Homophones are why it now reaches the times and not only the pairing: read aloud, `queue` comes back written `cue` and `rustle` comes back `Russell`, and without a word for it the written word is passed over and its time shared out among its neighbours.

### Fixed
- Deciding whether two spellings are the same word ignores the accents of the Latin alphabet and nothing else. It used to ignore every combining mark Unicode knows, which reached far past the alphabet that was meant for: `мой` matched `мои`, and Japanese and Devanagari words differing only by a mark matched each other. Those no longer match, and the times such words were given move. Letters carrying a stroke rather than an accent, `ł` and `đ` among them, are folded to their plain letter as before.
- Two spellings are compared by the letters a reader sees rather than by the characters Unicode stores: `é` written as one character and `é` written as `e` followed by an accent now count as one letter apiece, where they used to differ twice over. A pair that used to fall short of `threshold`, the bar for being the same word, can now clear it — in Latin text as much as anywhere else.

## 0.2.0

A Python port of this library now exists, and the two are held to one set of tuned numbers and one set of cases so they cannot come to disagree. Both carry the same major and minor version for that reason.

### Added
- `SilenceHold.held` carries each word's mark into the quiet behind it, and never into the word that follows. A recogniser marks where a word stops being audible, not where the voice has finished with it, so a passage played to the mark stops a hair short of itself. It is the one call that needs the recording.

### Changed
- Likeness is measured with diacritical marks lifted. A recogniser trained on plain Latin returns `casa` for `čaša` and `lodz` for `łódź`, and in a short word two lost marks put it under any usable bar: the word was not found at all, and the stretch it was given ran between its neighbours, so a mark following the reading sat on a word nobody was saying. `normalize` is unchanged, so a reader saying `zamek` for `żamek` is still not credited with it — lifting the marks is for finding where a word is, not for deciding whether it was said.
- The numbers the alignment is tuned to moved out of the source into `rules.yaml`, which every port reads.

### Fixed
- A token with no letters in it — a numeral, a stray mark — was joined onto its neighbour for free, because it adds nothing to the joined string and so cannot lower the likeness. `From 1999 fairest` gave `From` everything up to `fairest`. Such a token is now passed over.
- A weighting answering with something that is not a number was compared against the smallest allowed weight and won, because a comparison against such a value is false whichever way round it is put, and it then travelled into every span. It is read as one instead.

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
