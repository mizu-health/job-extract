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
// in — passages are the whole description in reading order, nothing dropped
[{
  "passages": ["Duties\n\nProvides anesthesia care …", "Benefits\n\nHealth insurance …"],
  "hints": { "schedule": [0, 1], "benefits": [1, 0], "duties": [0, 1] },
  "specialtySlugs": ["general-anesthesiology", "cardiac-anesthesia"]
}]

// out — nulls mean "nothing found", never empty strings or zeros
[{
  "callType": "IN_HOUSE_CALL", "callRatio": 6,
  "shift": "ROTATING", "shiftHours": [12],
  "scheduleDetails": null,
  "benefits": "Health insurance …", "incentiveCompensation": null,
  "responsibilities": "Provides anesthesia care …",
  "specialties": ["general-anesthesiology"]
}]
```

### Why passages, and why hints

The on-device window is 4,096 tokens covering instructions, input, schema and
output together. Most postings fit whole and arrive as a single passage; the
long tail does not, and a posting that overflows returns nothing at all rather
than a partial answer. So the caller splits on the boundaries the description
already has, blank lines first and sentence ends after.

`hints` set reading order per field group, most promising passage first. **Each
list names every passage.** It is an ordering, never a filter, and the Swift
side falls back to document order if that invariant is broken.

That distinction is the whole design. An earlier contract used the same keyword
matching to *select* excerpts, which meant a benefits section written in
unexpected words was never sent, and the result was indistinguishable from a
posting with no benefits at all. Now unfamiliar wording costs extra model calls
rather than the field.

Every group but one stops as soon as it is answered, which is what keeps the
cost close to the old design. Specialties are the exception: a subspecialty is
named once, anywhere, so that answer is a union over every passage.

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
