# Bar App Telemetry Spec, v1

This is the contract between a Bar App (ClaudeBar, CodexBar) that writes Telemetry and Bar UI, which reads it. Words in **bold** are defined in [CONTEXT.md](../CONTEXT.md). Why the spec exists at all is in [ADR 0001](adr/0001-written-telemetry-spec-no-shared-package.md).

MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

Bar UI drops any record that doesn't conform, counts what it dropped, and links that count back to this page.

## 1. Encoding

- Telemetry is OTLP/JSON, as defined by the [OTLP specification](https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding). Field names are lowerCamelCase, 64-bit integers are JSON strings, and enums are integers.
- Metrics are `ExportMetricsServiceRequest` objects. Logs are `ExportLogsServiceRequest` objects. There are no traces.
- One request per line, UTF-8, and every line ends with `\n`.

## 2. Files

| | |
|---|---|
| Folder | The **Telemetry Folder**. Default `~/Library/Application Support/<AppName>/Telemetry` (for example `~/Library/Application Support/ClaudeBar/Telemetry`). It isn't in Documents, because macOS asks the person to allow every app that reads or writes there. |
| Metrics file | `<service.name>-metrics-YYYY-MM-DD.jsonl` |
| Logs file | `<service.name>-logs-YYYY-MM-DD.jsonl` |
| Date in the name | The UTC date the record was written. |
| Permissions | Files `0600`. A folder the Bar App creates is `0700`. A folder that already exists keeps its permissions, because it may be one the person chose. |

Writers:

- MUST only append. MUST NOT rewrite or reorder earlier lines.
- MUST NOT leave a partial line that later data gets appended after. If the file doesn't end in `\n` (say after a crash), the writer truncates back to the last `\n` before appending.
- MUST delete old data a whole file at a time, by the date in the file name. A retention of `0` means keep forever. Only files that match the two name patterns above are ever deleted.

Moving from the old default. The default used to be `~/Documents/<AppName> Telemetry`. When a Bar App starts with no folder chosen and that old folder exists, it:

- MUST move the files matching its two name patterns into the new default before writing anything. A file whose name is already in the new folder has its complete lines appended to that file instead.
- MUST NOT touch any other file in the old folder. The one exception is a `.DS_Store`: when it is the only thing left, the Bar App deletes it and removes the folder. Otherwise the folder stays.
- MUST NOT follow the old folder if it is a symbolic link.
- MUST NOT append a file's lines twice. If a moved file can't be deleted afterwards, a later launch must not append it again.
- Once none of its files are left in the old folder, MUST record that the move is done and stop checking Documents on later launches. Checking it is what makes macOS ask.
- MUST keep writing to the new default even if moving a file fails.

A reader looks in the new default first. It reads the old folder only while the new one doesn't exist, which is the case for a Bar App build from before the move.

Readers:

- MUST read only complete, `\n`-terminated lines.
- MUST expect a file to disappear at any moment, because of retention.
- MUST NOT take locks or write anything into the Telemetry Folder.

## 3. Resource and scope

Every `ResourceMetrics` and `ResourceLogs` MUST carry these resource attributes:

| Attribute | Value |
|---|---|
| `service.name` | `claudebar` or `codexbar`, always lowercase |
| `service.version` | The app's marketing version |
| `host.name` | The Mac's host name |
| `os.type` | `darwin` |
| `bar.spec.version` | `"1"` |

A record without `bar.spec.version` = `"1"` doesn't conform.

The instrumentation scope name is `com.gordonbeeming.<AppName>.telemetry` (for example `com.gordonbeeming.ClaudeBar.telemetry`). The scope version is the app version.

## 4. Metrics

Bar UI reads the `bar.*` metrics below. A Bar App MAY also write metrics under its own prefix (`claude.*`, `codex.*`). Bar UI only reads the ones listed in the appendix.

### 4.1 Limits

A **Limit** is identified by `limit.id`, which MUST stay the same for the same Limit for as long as the AI tool keeps it. That holds across app versions and across the tool renaming its labels.

| Attribute | Required | Meaning |
|---|---|---|
| `limit.id` | yes | Stable ID. Claude: the API's limit `kind`, plus `:<model id>` when the limit is scoped to a model (for example `session`, `weekly_all`, `weekly_scoped:claude-opus-4-1`). When the API gives a scoped limit only a display name and no model ID, use `<kind>:<display name>` (for example `weekly_scoped:Fable`). Codex: `<bucket id>:<window minutes>` (for example `codex:10080`), because Codex's `primary` and `secondary` labels can swap between plans. When Codex doesn't report the window length, use `<bucket id>:<window label>` (for example `codex:primary`). Both fallbacks are a last resort, because the ID changes if the tool renames or swaps the label. Bar UI then sees a new Limit, and the old one disappears. |
| `limit.name` | yes | Display name, for example `Weekly · Opus` |
| `limit.window.duration_minutes` | when known | The **Window** length as an int, for example `300` or `10080`. Leave it out when the Bar App doesn't know it; never write `0`. Bar UI still shows the Limit, without the Window length. |
| `model.id` | only when the tool says the Limit applies to one model | Never inferred. Codex doesn't scope its Limits to models today, so CodexBar leaves it out. |

| Metric | Type | Unit | Value |
|---|---|---|---|
| `bar.limit.utilization` | Gauge | `%` | 0 to 100, as a double |
| `bar.limit.resets_at` | Gauge | `s` | When the current Window ends, as Unix seconds |

Both are written every sample, for every Limit the tool currently reports.

### 4.2 Tokens

| Metric | Type | Unit |
|---|---|---|
| `bar.tokens` | Sum, cumulative (`aggregationTemporality: 2`), `isMonotonic: true` | `{token}` |

| Attribute | Required | Meaning |
|---|---|---|
| `model` | yes | The model ID exactly as the tool reports it. When the tool reports usage without a model, the tokens still count, under the model `unknown`. Bar UI shows those as "No pricing". |
| `token.type` | yes | One of the **Token Types** below |

| `token.type` | Counts |
|---|---|
| `input` | Input tokens that were neither read from nor written to the cache |
| `cache_read` | Input tokens read from the cache |
| `cache_write_5m` | Input tokens written to the cache with a 5-minute lifetime |
| `cache_write_1h` | Input tokens written to the cache with a 1-hour lifetime |
| `cache_write` | Input tokens written to the cache when the tool doesn't report a lifetime and has no documented default. (Claude's default is 5 minutes, so ClaudeBar counts an unsplit write as `cache_write_5m`.) |
| `output` | All output tokens, reasoning included |
| `reasoning` | The reasoning part of `output`. Bar UI never adds this on top of `output`. |

Rules:

- `startTimeUnixNano` is when this count started: when Tracking was turned on, or when the counters were reset. When the counters restart, the start time MUST change, so Bar UI can tell a restart apart from a drop.
- Only tokens seen after the start time are counted. There is no backfill.
- A point is written only for a `model` and `token.type` pair that has counted something. Bar UI treats a missing pair as zero, so no zero points are needed.
- Every count is attributed to the model that produced it. Codex takes the model from the session's turn context, per turn.
- Codex's `input_tokens` already includes cached tokens. CodexBar MUST subtract `cached_input_tokens` so that `input` means the same thing for both apps. Codex doesn't say whether `cache_write_input_tokens` is inside `input_tokens` too, so CodexBar decides per event: when `total_tokens` equals `input_tokens + output_tokens`, the cache writes are inside input and are subtracted as well.
- Codex sometimes repeats a `token_count` event with the same running total. CodexBar MUST skip a total it has already counted, so nothing is counted twice.

### 4.3 Perks

| Metric | Type | Value |
|---|---|---|
| `bar.perk.available` | Gauge | For `reset_credit` and `guest_pass`: how many are available. For `credit_grant`: the amount available in major units of `perk.currency` (dollars, not cents), converted with the currency's ISO 4217 exponent. |

| Attribute | Required | Meaning |
|---|---|---|
| `perk.kind` | yes | `reset_credit`, `guest_pass` or `credit_grant` |
| `perk.currency` | for `credit_grant` | ISO 4217 code, for example `USD` |
| `perk.id` | if the tool identifies each Perk | The tool's own id for one Perk, a string. A point with a `perk.id` stands for that one Perk. |
| `perk.expires_at` | if known | Unix seconds, as an int. On a point it is the earliest expiry among the Perks that point counts, which is that Perk's own expiry when the point carries a `perk.id`. |

Bar UI keys a Perk series on `perk.kind` and `perk.currency` only. Every other attribute on the gauge, `perk.expires_at` and `perk.id` included, is information and can change from sample to sample without starting a new series.

When the tool identifies each Perk, the Bar App MUST write one point per Perk, each carrying its `perk.id`, plus `perk.expires_at` when it is known, so that each Perk's expiry is kept. A single point for three Perks would keep only the earliest of their expiries. Bar UI lists each such point as its own line and adds the points up for the series total. Points without a `perk.id` that share a key (two Guest Pass campaigns, say) are added into one line.

## 5. Events (logs)

- The event name MUST go in the LogRecord's top-level `eventName` field, and nowhere else (not the body, not an attribute).
- `severityNumber` is `9` (INFO). `timeUnixNano` and `observedTimeUnixNano` are both set.
- `body` MAY hold a short sentence for people to read. Bar UI ignores it.
- A Bar App MAY write its own events under its own prefix (`claude.*`, `codex.*`). Bar UI ignores event names and metric names it doesn't know; they don't count as non-conforming. Only a record that is missing `bar.spec.version`, or a `bar.*` record that breaks this spec, counts as non-conforming.

| `eventName` | When | Attributes |
|---|---|---|
| `bar.tracking.started` | Tracking turns on, or the counters restart | `tracking.interval_minutes` |
| `bar.limit.appeared` | A Limit is seen for the first time | the Limit attributes from 4.1 |
| `bar.limit.reset` | A Limit's Window rolled over | the Limit attributes, plus `limit.utilization.last` (the last sampled utilisation before the reset) and `limit.resets_at.next` |
| `bar.limit.disappeared` | The tool stops reporting a Limit | the Limit attributes |
| `bar.perk.available` | A Perk appears, or its count or amount goes up | `perk.kind`, `perk.quantity`, `perk.currency` for a Credit Grant, `perk.id` if the tool provides one, `perk.expires_at` if known |
| `bar.perk.gone` | A Perk disappears, or its count or amount goes down | the same, plus `perk.gone.reason` (`used` or `expired`), but only when the Bar App knows it |

`perk.quantity` is how much appeared or went in this one event: a count for `reset_credit` and `guest_pass` (an int), an amount in major units for `credit_grant` (a double). It is always positive. When it's missing on a `reset_credit` or `guest_pass` event, Bar UI takes it as `1`. When it's missing on a `credit_grant` event, the amount is unknown: Bar UI records the event without an amount. A Bar App can write one event per Perk (CodexBar does, with each credit's `perk.id`) or one event for the whole change (ClaudeBar does).

Perk events come from a change in the count or amount. When the tool also lists individual Perks, that list may be capped, so a Perk showing up in the list or dropping out of it isn't on its own proof that it appeared or went.

When `perk.gone.reason` is missing, Bar UI decides the reason itself:

- **Expired**: the Perk disappeared at or after its known `perk.expires_at`.
- **Used**: it disappeared before then, or a redemption is on record.
- **Reason unknown**: no expiry is known.

## 6. Tracking settings

Each Bar App owns its Tracking settings ([ADR 0003](adr/0003-bar-apps-own-their-tracking-settings.md)).

### 6.1 Reading

Bar UI reads these keys from the Bar App's defaults domain (its bundle ID) and never writes them:

| Key | Type | Meaning |
|---|---|---|
| `telemetryEnabled` | Bool | Tracking on or off |
| `telemetryIntervalMinutes` | Int | 1 to 1440. A Bar App accepts any value in range, not only its picker presets. |
| `telemetryRetentionDays` | Int | 0 means forever, otherwise 1 to 3650 |
| `telemetryDirectory` | String | Absolute path of the Telemetry Folder. Missing means the default. |

### 6.2 Changing: URL scheme

| App | Scheme |
|---|---|
| ClaudeBar | `claudebar://` |
| CodexBar | `codexbar://` |

- **`<scheme>://telemetry?enabled=1&interval=5&retention=0&folder=<percent-encoded path>`**
  - Any subset of the parameters is allowed. Unknown parameters are ignored.
  - The Bar App MUST show a confirmation that lists each change (old value, then new value) before applying anything. Any app or web page can open this URL, so it is never applied silently.
  - On confirm, the change applies immediately. There is no separate "Apply" step.
  - An invalid value rejects the whole request and says why.
- **`<scheme>://settings`** opens the Bar App's settings window.

The Bar App writes the new values to its defaults domain, and Bar UI picks them up from there.

## 7. Appendix: app-specific metrics Bar UI reads

| Metric | App | Shown as |
|---|---|---|
| `claude.extra_usage.enabled`, `.used_credits`, `.monthly_limit` | ClaudeBar | Extra usage on the ClaudeBar page |

## 8. Changing this spec

- A change that would make an older reader misread data bumps `bar.spec.version`.
- Adding optional attributes, events or appendix metrics doesn't.
- Bar UI drops records from a spec version it doesn't know, and says so.
