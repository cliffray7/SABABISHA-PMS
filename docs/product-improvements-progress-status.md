# Proposed Project Progress and Status Rules

**Status:** Approved, subject to pre-implementation verification  
**Date:** 2026-10-08  
**Roadmap:** [Safe Product Improvements Roadmap](product-improvements-roadmap.md)  
**Inventory:** [Product Improvements Phase 0 Inventory](product-improvements-inventory.md)  
**Assignment decisions:** [Project Assignment and Ownership](product-improvements-project-assignment.md)  
**Approval record:** [Product Improvements Owner Decision Record](product-improvements-owner-decisions.md)

## Current behavior

- Project status is stored as one of `PLANNING`, `ACTIVE`, `ON_HOLD`, or `COMPLETED`.
- Task status is stored as one of `TO DO`, `IN PROGRESS`, `REVIEW`, or `DONE`. Subtasks use `TO DO`/`DONE` in the current API.
- The task-list endpoint returns active, non-deleted top-level tasks and includes subtask counts. Subtasks are not included in that task list.
- Both Web and Flutter compute the dashboard completion percentage in the client. Organization admins/owners and project managers/team leads see the selected project's top-level tasks; other users see only their own assigned tasks. The same “Project health” label therefore represents a project-wide measure for some roles and personal completion for others.
- Both clients currently show `0%` when the selected task set is empty. The dashboard API does not provide this progress calculation.
- Task completion, outstanding work, overdue counts, due dates, and task status distribution are already available from current task data. The UI displays task workflow labels such as “Review” and “Completed.”

## Recommended shared progress definition

Use a server-calculated **project-wide task completion** measure:

```text
eligible tasks = non-deleted top-level tasks in the active project
completed tasks = eligible tasks whose status is DONE
progress percent = round(100 * completed tasks / eligible tasks)
```

- Exclude subtasks from the project percentage to avoid counting parent and child work twice. Continue showing subtask completion separately for each parent task.
- Include all eligible project tasks regardless of assignee, priority, or status other than `DONE`.
- Exclude soft-deleted tasks. Exclude tasks in archived/trashed projects from active project tracking. Permanent purge is not part of the calculation.
- If there are no eligible tasks, represent progress as “no tasks yet” (`hasTasks: false`, no percentage) rather than implying that an empty project is 0% complete. A numeric compatibility field may remain `0` for older consumers if needed, but new UI must use the explicit empty flag.
- Calculate outstanding count as eligible tasks with status other than `DONE`; calculate overdue count from outstanding tasks with a due date before the agreed organization/project-local current date.
- Use one response contract for Web and Flutter. Do not recompute project-wide percentage from whichever tasks happen to be visible in a client.

The formula is a proposal, not an approved denominator. Confirm whether cancelled tasks (no current cancelled value exists), archived projects/tasks, soft-deleted/trashed tasks, and subtasks count; confirm empty-project representation, the date/time zone for overdue work, and whether every project member may see the aggregate. The existing membership/read policy remains authoritative; showing an aggregate must not expose additional task details. See the independent approval record before any implementation.

## Keep project and task status separate

Project status describes the lifecycle of the project. Task status describes an item's work state. Do not mix them into one status list.

| Scope | Existing stored value | Possible display wording | Proposal |
|---|---|---|---|
| Project | `PLANNING` | To Do / Planned | Keep the stored value. Confirm the wording; “To Do” may be confusing for a whole project. |
| Project | `ACTIVE` | In Progress | Keep the stored value and use “In Progress” as a display label if accepted. |
| Project | `ON_HOLD` | On Hold | Existing value and wording already match. |
| Project | `COMPLETED` | Completed / Done | Keep “Completed” for projects; reserve “Done” for tasks if that distinction is clearer. |
| Task | `TO DO` | To Do | Existing value and wording. |
| Task | `IN PROGRESS` | In Progress | Existing value and wording. |
| Task | `REVIEW` | Under Testing / Review | Do not relabel to “Under Testing” unless review specifically means QA/testing in this product. |
| Task | `DONE` | Done / Completed | Existing value; clients may display “Completed.” |
| Project or task | no `PENDING` value | Pending | Do not add or alias until the owner defines what is pending, who it is pending on, and whether it is a project or task state. |

Keep persisted values and meanings unchanged until the mappings are reviewed and approved. If display aliases are approved, centralize the mapping and ensure filters, reports, validation, and older clients continue using the existing values. New persisted statuses require a separate transition matrix, API validation update, client rollout plan, and data/report compatibility review. Only the owner-approved terminal task status or statuses count as completed in the numerator.

## Candidate tracking surface

After progress/status decisions and assignment semantics are approved, expose one project tracking summary to the agreed project-member audience:

- accountable owner and active participants (from the assignment/ownership proposal);
- project status and due date;
- project-wide completion and “no tasks yet” state;
- outstanding and overdue counts;
- task status distribution and current open tasks, with existing task access rules;
- per-task assignees and separate subtask completion indicators.

Refresh the server-derived summary through authenticated REST after existing project/task changes and existing SignalR invalidation events. Apply the same meaning in Web and Flutter. Keep personal workload metrics separately labelled; never present them as project completion.

## Proposed API direction after approval

- Add an additive project-tracking summary field or route, computed server-side from the same eligible-task predicate for every client.
- Include counts, `hasTasks`, progress percentage when defined, status, due date, and owner/member identifiers required by accepted UI decisions.
- Enforce active project membership, organization membership, tenant isolation, and archived/trashed project behavior on the server.
- Keep existing project/task status values and response fields intact for older clients. Do not require schema changes for a derived progress field.
- Add tests for empty projects, parent/subtask combinations, mixed task states, deleted tasks, archived/trashed projects, tenant isolation, and consistent role-visible aggregate behavior.

## Owner decisions

- [x] Include all non-deleted top-level tasks regardless of assignee; exclude subtasks and soft-deleted tasks. Only `DONE` counts completed. Archived/trashed projects are excluded from active tracking; historical summary is allowed only if current access policy permits it. No cancelled task status currently exists.
- [x] Show “No tasks yet” when the eligible-task count is zero.
- [x] Active project members may see aggregate progress; individual task details retain existing access rules.
- [x] Use project time zone if configured, otherwise organization time zone, then a documented system default. Project currently has no time-zone field; `Organization.Timezone` defaults to UTC.
- [x] Project labels: `PLANNING` → Planned; `ACTIVE` → In Progress; `ON_HOLD` → On Hold; `COMPLETED` → Completed.
- [x] Task labels: `TO DO` → To Do; `IN PROGRESS` → In Progress; `REVIEW` → In Review; `DONE` → Done. Only `DONE` counts as completed.
- [x] Do not add `PENDING` until a distinct workflow is defined.
- [x] Web and Flutter are both release targets.
