# AI Engineering Instructions

This repository uses persistent engineering context. Before performing development work, read in order:
1. context/project-overview.md
2. context/architecture-context.md
3. context/ui-context.md
4. context/code-standards.md
5. context/ai-workflow-rules.md
6. context/progress-tracker.md

Then read the active specification under:
context/feature-specs/

These documents are authoritative. If implementation conflicts with documentation, do not silently choose one. Investigate the discrepancy.

## Mandatory Workflow

READ → UNDERSTAND → PLAN → IMPLEMENT → TEST → VERIFY → UPDATE CONTEXT

Do not make unrelated changes.
Do not invent missing business requirements.
Do not weaken architecture or security to make a feature work.

After every meaningful implementation:
- update progress-tracker.md
- update affected context documentation
- run relevant verification
- report actual verification results

Never claim a test/build succeeded unless it was run.
