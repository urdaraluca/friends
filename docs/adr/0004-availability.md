# ADR 0004: Availability heatmap

- **Status:** Accepted
- **Date:** 2026-09-26
- **Related:** issue #16, [contract section 13](../api/contract.md).

## Context

The spec asks for members to mark when they are free, with the best overlap days highlighted
automatically. Friends usually share several groups. The data is personal: saying you are busy is
a small social signal.

## Decision

| Question | Decision | Why |
|---|---|---|
| Scope | **Per user**, shown in every group the user is in | Nobody answers the same question in each group. Nothing needs cleaning up when a membership ends. |
| Granularity | A date plus `all_day`, `morning`, `afternoon` or `evening` | Enough to plan "an evening" versus "a whole day" without a full time grid. |
| Combining slots | A part of the day falls back to the `all_day` answer. A day without an `all_day` answer is free if all parts are free, maybe if any is free or maybe, busy if all are busy, else unknown. | Simple to explain, and one busy morning doesn't make the whole day look busy. |
| Score | `free + 0.5 × maybe`; ties go to fewer busy, then the earlier date. Up to 10 best days. | A "maybe" is worth something but less than a "yes". Earlier dates break ties because they're the ones to act on. |
| Privacy | Counts for everyone. Names only for free and maybe. **Busy is never attributed.** | Knowing who is free is what you need to plan. Who said no isn't. |
| Who counts | Current members only | Former members' answers must not skew a group's plans. |
| Range | At most 92 days per request | About three months: a heatmap page, bounded work on the Pi. |
| Writes | `PUT` replaces my answers within a date range | The editor saves the visible range in one go, with no per-cell requests. Clearing is just leaving a slot out. |

## Consequences

- The client edits a range and sends it back whole. There is no per-entry endpoint.
- The heatmap is computed on request from the current members' rows. At a group's scale (at most 100
  members × 92 days × 4 slots) this is cheap. No cache is needed.
- A future "busy with reason" or per-group override would be a new table, not a change to this one.
