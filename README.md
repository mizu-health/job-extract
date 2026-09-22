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
| `salary` | Batch salary extraction. Production path. |
| `enrich` | Batch field extraction: call, schedule, benefits, duties, specialties. Production path. |
| `extract` | General field extraction. Placeholder schema, still being designed. |
| `salaryprobe` | Development only: runs fixed fixtures and prints what the model said next to what was expected. |

## The salary contract

This is consumed by `CLIModelFallback` in the `api` repository
(`internal/ingest/salary_cli.go`). **The two are versioned separately, so
changing either side of this shape breaks the other silently** — a mismatch
shows up as the fallback quietly returning nothing rather than as an error.
After changing it, run the integration test on the Go side:

```sh
MIZU_EXTRACT_BIN=$(pwd)/.build/debug/mizu-extract \
  go test ./internal/ingest/ -run Integration -v
```

Input on stdin, output on stdout, positionally aligned and the same length:

```jsonc
// in
[{ "description": "Comp is 245k base plus a 20k sign on bonus." }]

// out — nulls mean "nothing found", never zeros
[{ "min": 245000, "max": null, "unit": "YEAR" }]
```

`unit` is one of `HOUR`, `DAY`, `WEEK`, `MONTH`, `YEAR`.

Descriptions arrive pre-excerpted around their money tokens, so they are short
passages rather than whole postings.

## The enrich contract

Consumed by `CLIModelEnricher` in the `api` repository
(`internal/ingest/enrich_cli.go`), and versioned separately in the same way the
salary contract is. Run the Go integration test after changing either side.

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
model's output, not its honesty. Nothing it returns is trusted directly, and the
Go side re-checks everything against plausibility bands.

What observation established, and why the code looks like this:

- **It reads well and abstains badly.** It read every real pay format correctly,
  then produced a confident figure for every case whose right answer was
  "nothing" — including a `$50-$100M` project budget as an hourly wage, and
  zeros for a posting with no pay at all. The caller only asks about
  descriptions that contain a money token, which removes the worst of it.
- **It is not deterministic on unstated units.** Asked twice about "Comp is 245k
  base", it answered `YEAR` once and `MONTH` the next run. The Go side discards
  the proposed unit whenever the text names no period and derives it from
  magnitude instead.
- **Suffixes need spelling out.** It read "190k to 215k" as 190 and 215 until the
  `@Guide` said explicitly to write 190k as 190000.
- **Absence must be described as null.** Left to itself it writes `"not stated"`
  into a string field and `0` into a number. `Sanitize` scrubs the first; the
  contract above forbids the second.

The bias throughout: a null field is a good outcome, an invented one is not.
Prefer deterministic rules wherever a rule can do the job, and reserve the model
for what rules genuinely cannot reach.
