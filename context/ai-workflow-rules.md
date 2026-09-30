# AI Workflow Rules

## 1. Mandatory Context
Before changing code, read:
1. project-overview.md
2. architecture-context.md
3. ui-context.md
4. code-standards.md
5. progress-tracker.md
6. current feature specification

Do not implement before understanding these files.

## 2. Core Rule
Understand → Plan → Implement → Verify → Document
Never jump directly from request to large implementation.

## 3. Scope Discipline
Implement ONLY the requested feature.
Do not:
- redesign unrelated code
- rename unrelated files
- change architecture unnecessarily
- add unrelated dependencies
- perform speculative refactoring

## 4. Before Coding
Determine:
- requested outcome
- affected layers
- affected files
- dependencies
- security implications
- tenant implications
- possible regressions

## 5. Missing Requirements
NEVER silently invent important requirements.
If ambiguity materially affects architecture, security, data, permissions or business behaviour:
STOP and ask. Record unresolved questions in progress-tracker.md.

## 6. Existing Code
Before creating something new: SEARCH the repository.
Determine whether equivalent:
- component
- service
- helper
- hook
- endpoint
- DTO
- model
already exists. Reuse before duplicating.

## 7. Architecture Protection
Do not violate architectural invariants.
Architecture changes require explicit justification.
Significant decisions should create/update an ADR (Architecture Decision Record).

## 8. Database Changes
Never modify schema casually.
Required:
1. understand existing model
2. determine migration impact
3. create migration
4. preserve existing data
5. evaluate rollback
6. test

## 9. Security
Never:
- expose secrets
- disable authentication
- bypass authorization
- weaken tenant isolation
- log sensitive credentials
- hard-code production secrets

## 10. Debugging
When something fails: DO NOT randomly modify files.
Follow: Observe → Reproduce → Gather evidence → Identify root cause → Propose fix → Apply minimal fix → Verify → Regression test
Use current-issues.md for complex bugs.

## 11. Protected Files
Do not modify generated/vendor/library-managed files unless explicitly required.
List project-specific protected paths here:
- Migration snaphosts (`*Snapshot.cs`)
- `.git/`

## 12. Verification
After implementation run appropriate:
- format
- lint
- typecheck
- unit tests
- integration tests
- build

Never claim success without verification.

## 13. Documentation Sync
If architecture changed: update architecture-context.md
If standards changed: update code-standards.md
If UI system changed: update ui-context.md
If scope changed: update project-overview.md
Always update progress-tracker.md after meaningful work.

## 14. Completion Report
Report:
- Changed
- Created
- Deleted
- Tests run
- Build result
- Known limitations
- Next recommended task
