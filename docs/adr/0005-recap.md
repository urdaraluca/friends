# ADR 0005: Group recap

- **Status:** Accepted
- **Date:** 2026-09-26
- **Related:** issue #17, [contract section 14](../api/contract.md).

## Context

The spec asks for a "Wrapped"-style recap: a month's or a year's highlights for a group (the most
active planner, the memories made, the top category). The MVP has recorded what this needs from day
one: `group_log` with actors, `completed_at`, `accepted_at`, and `created_at` on interests and votes.

## Decision

| Question | Decision | Why |
|---|---|---|
| Periods | Calendar months and years in the **group's** timezone. Only past and current ones. | A group lives in one place. "October" must mean the same days for everyone, whatever their phone says. |
| Parameters | `period` plus an optional `start` (the period's first day); omitted, it is the current period | One endpoint covers the monthly and yearly recaps and the "this month so far" view. |
| Planner score | One point for each idea, event or poll created, and for each activity marked done | Each is a planning action. Counting them the same keeps it explainable ("12 plans"). |
| Top category | Top-level categories; subcategories count under their parent | "Outdoors" means more at a glance than "Hiking" split from "Cycling". |
| "Most wanted" | The idea with the most interest by the period's end, **still** in the backlog today | The point is to nudge: an idea that already happened isn't wanted anymore. |
| Caching | **None.** Computed on request from the rows as they are now. | GET handlers never write (contract section 1.7), and a year of one group is a few thousand rows. A cache would also need invalidating when an activity is deleted or recategorized. |
| Deleted data | Follows the current rows: a deleted activity leaves the memories. A deleted account's log rows count in the totals, not as a planner. | Nobody wants a deleted item in a shareable recap. |

## Consequences

- A past recap can change when its activities are edited or deleted. The recap reflects the group's
  current memory of the period, which is what people share.
- If a recap ever gets slow (Postgres, bigger groups), a background job can fill a `recaps` table for
  completed periods without changing the API.
- The demo seed spreads a year of history (`friends_api/demo/history.py`). It moves the log rows to
  the moments the backdated rows describe, and records who marked each done activity.
