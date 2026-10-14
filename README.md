# mizu-extract

Structured field extraction for job listings, using the on-device Apple
Foundation Models framework.

A pure function over stdin/stdout: no network, no database, no knowledge of the
API. The Go crawler in the `api` repository pipes listings through this binary
and decides for itself what to do with the result. Swapping the model out means
replacing this binary, not touching the pipeline.

## Requirements

macOS 26+ with Apple Intelligence enabled. Plain SwiftPM — no Xcode project.

```sh
swift build
swift run mizu-extract probe    # check the model is reachable
swift test
```

## Commands

| Command | Purpose |
|---|---|
| `probe` | Report model availability and run a round-trip. Start here if anything misbehaves. |
| `enrich` | Batch field extraction: call, schedule, benefits, duties, specialties. Production path. |

## The enrich contract

This is consumed by `CLIModelEnricher` in the `api` repository
(`internal/ingest/enrich_cli.go`). **The two are versioned separately, so
changing either side of this shape breaks the other silently.** A mismatch
shows up as fields quietly coming back empty rather than as an error. After
changing it, run the integration test on the Go side:

```sh
MIZU_EXTRACT_BIN=$(pwd)/.build/debug/mizu-extract \
  go test ./internal/ingest/ -run Integration -v
```

Input on stdin, output on stdout, positionally aligned and the same length:

```jsonc
// in
[{
  "description": "Duties\n\nProvides general and cardiac anesthesia care …",
  "specialtySlugs": ["general-anesthesiology", "cardiac-anesthesia", "pediatric-anesthesia"]
}]

// out (a real response; fields the model found nothing for are left out)
[{
  "benefits": "Health insurance, 401(k) match, 6 weeks PTO and $5,000 CME allowance.",
  "callRatio": 6, "callType": "HOME_CALL",
  "responsibilities": "Provides general and cardiac anesthesia care to adult patients in the OR. Supervises CRNAs.",
  "scheduleDetails": "Three 12-hour day shifts per week. Call is 1 in 6, taken from home.",
  "shift": "DAY", "shiftHours": [12],
  "specialties": ["general-anesthesiology", "cardiac-anesthesia"]
}]
```

A missing field means "nothing found". It is never an empty string or a zero.
A posting where nothing was found is `{}`, so the output stays aligned with the
input. A null or missing `specialtySlugs` skips the specialty question rather
than failing the batch.

`overflowed`, when present, names the field groups whose prompt did not fit the
context window (`"overflowed": ["benefits"]`). That separates "the description
says nothing about benefits" from "we never managed to ask".

### Why the whole description

An earlier version had Go select excerpts by keyword and send only those. A
section written in words the keyword lists did not know was never sent, and the
result looked exactly like a posting with no such section. Measured on the same
40 federal postings, the keyword rules found call in 2% of them against the
model's 60%.

The on-device window is 4,096 tokens, covering instructions, input, schema and
output together. Measured descriptions run about 1,400 tokens at the median and
2,000 at the longest, so they fit whole. Rather than build splitting for a
problem that has not appeared, the rare posting that does not fit is reported
in `overflowed`. That field is the signal for whether splitting is worth
building.

### How a posting is read

Five separate model calls over the same text: call, schedule, benefits, duties
and specialties. Asked about call alongside hours in one call, the model
answered the hours and left call null even where the text described it plainly.

Benefits, incentives, duties and the schedule sentence are verbatim copies, not
summaries, because a copy can be checked: Go rejects any span that does not
appear in the source. Swift runs the same check first and asks once more when
the model reworded instead of copying. On federal postings the model paraphrased
benefits about half the time on the first ask, and the second ask recovers
about half of those.

Specialties are chosen from the site's own vocabulary, sent in the request, and
Go checks them against that list again on the way back.

## Design notes

Guided generation (`@Generable` / `@Guide`) constrains the *shape* of the
model's output, not its honesty. Nothing it returns is trusted directly. The Go
side checks every copied passage against the source text, every enum against a
closed set, and every specialty against an allow-list.

Most of what shaped the code was learned on this tool's first job, a salary
extractor. That was later removed: measured against 143 live postings, plain
label patterns resolved every one that published pay, so the model earned
nothing there. The lessons carried over to `enrich`:

- **It reads well and abstains badly.** It read every real pay format correctly,
  then produced a confident figure for every case whose right answer was
  "nothing", including a `$50-$100M` project budget as an hourly wage, and
  zeros for a posting with no pay at all.
- **It is not deterministic on unstated facts.** Asked twice about "Comp is 245k
  base", it answered `YEAR` once and `MONTH` the next run.
- **Shorthand needs spelling out.** It read "190k to 215k" as 190 and 215 until
  the `@Guide` said explicitly to write 190k as 190000.
- **Absence must be described as null.** Left to itself it writes `"not stated"`
  into a string field and `0` into a number. `Sanitize` scrubs the first; the
  contract above forbids the second.

The bias throughout: a null field is a good outcome, an invented one is not.
Prefer deterministic rules wherever a rule can do the job, and reserve the model
for what rules genuinely cannot reach.
