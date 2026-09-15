# Harness evolution

Record only durable, approved lessons that make future agent work safer or more
reliable. Do not store prompts, transcripts, secrets, customer data, internal
URLs, or one-off mistakes.

## Operating rule

When a failure pattern appears at least twice, capture the smallest control that
would have prevented or detected it. Prefer a deterministic check over prose;
prefer project context over a global rule; use a skill only when the pattern
recurs across projects.

## Candidate lessons

| Repeated signal | Evidence | Proposed control | Owner | Status |
| --- | --- | --- | --- | --- |
| [short pattern] | [sanitized links or test names] | [test, lint, fixture, context, or skill] | [role] | [proposed/accepted/rejected] |

## Accepted controls

| Date | Control | Why it exists | Location | Review date |
| --- | --- | --- | --- | --- |
| [YYYY-MM-DD] | [short statement] | [repeated failure prevented] | [path/command] | [YYYY-MM-DD] |
