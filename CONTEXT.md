# bar-ui

A desktop dashboard that shows the telemetry Gordon's menu bar apps record about AI coding tool usage.

## Language

**Bar App**:
One of Gordon's menu bar apps that watches an AI coding tool's usage limits and can record telemetry about it. The set is closed and known in code: ClaudeBar and CodexBar today.
_Avoid_: source, plugin, provider

**Dashboard**:
This app, shipped as Bar UI. It finds installed Bar Apps, reads their Telemetry, and shows it.
_Avoid_: viewer, monitor

**Tracking**:
A Bar App's own opt-in switch that makes it record Telemetry. Only the Bar App changes it; the Dashboard asks the Bar App to change it.
_Avoid_: telemetry enabled, collection, logging

**Telemetry**:
The OpenTelemetry metrics and log events a Bar App writes to local files while Tracking is on. Not the AI coding tools' own OTel export.
_Avoid_: OTel data, stats, analytics

**Telemetry Folder**:
The folder a Bar App writes its Telemetry to. Each Bar App chooses its own, so the Dashboard asks where it is rather than assuming.

**Overview**:
The Dashboard view that combines Telemetry from every Bar App that has any.
_Avoid_: home, summary, all

**Menu Bar Preview**:
The small panel that opens from the Dashboard's menu bar icon. It shows recent usage and Burn Rate without opening the full window.
_Avoid_: popover, widget, mini view

**History**:
Telemetry left in a Telemetry Folder from earlier Tracking. It stays visible after Tracking is turned off, and gaps from Tracking having been off are shown as they are.

**Archive**:
The Dashboard's own permanent record of all Telemetry it has ever imported. It outlives the Bar Apps' files, which a Bar App deletes after its retention period.
_Avoid_: cache, database

**Telemetry Spec**:
The written contract in this repo that every Bar App's Telemetry must follow. Telemetry that doesn't match it is dropped and reported as non-conforming.
_Avoid_: schema, format

### Usage

**Token Type**:
One of: input (not from cache), cache read, cache write (5 minute), cache write (1 hour), output, and reasoning. Reasoning is a part of output, so totals never add it on top of output.

**API Cost**:
What a set of tokens would have cost at the AI vendor's public API prices, shown in the configured currency (A$ by default). It is a what-if figure, not money actually spent. Tokens for a model with no known price have no API Cost and are never priced by guessing.
_Avoid_: spend, cost, price

### Limits

**Limit**:
A cap a Bar App reports on how much of an AI coding tool can be used, measured as utilisation from 0 to 100%.
_Avoid_: quota, rate limit, bucket

**Window**:
The repeating period after which a Limit resets, with a duration the Bar App reports. Each Bar App has its own set of Windows (Claude: 5 hour and weekly, some per model; Codex: weekly only today). None are assumed.

**Burn Rate**:
How fast a Limit's utilisation has been rising recently, in percentage points per hour. For tokens, it is tokens per hour.
_Avoid_: velocity, pace (Pace is a later, separate idea)

**Unused at Reset**:
The headroom a Limit still had in the last sample before its Window reset.
_Avoid_: wasted, leftover

**Reset Credit**:
A Codex credit that resets a Limit early when it is redeemed.

**Guest Pass**:
A Claude referral pass that can be given to someone else.

**Credit Grant**:
Money credited to a Claude account for extra usage.

**Perk**:
Any Reset Credit, Guest Pass or Credit Grant. A Perk is available, then gone, and it goes either because it was used or because it expired.
_Avoid_: redemption token, offer

## Relationships

- The **Dashboard** reads the **Telemetry** of zero or more **Bar Apps**, and never changes it.
- A **Bar App** is in one of these states: not installed, installed without **Tracking**, installed without **Tracking** but with **History**, or **Tracking**.
- The **Overview** combines every **Bar App**; each **Bar App** also has a page of its own.

## Flagged ambiguities

- "OTel data" could mean a Bar App's **Telemetry** or the AI coding tools' own OTel export. Resolved: the Dashboard reads only **Telemetry**. The CLIs' own export is out of scope for now.
