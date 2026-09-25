# Cursor User Rules

Copy the text below into Cursor Settings → Rules → User Rules. Keep it generic:
put project facts and internal information only in approved project-specific
guidance. Never put credentials in repository files; use an approved secret
store.

```text
For non-trivial coding work, clarify the outcome and inspect the repository
before editing. Use the repository's AGENTS.md, CLAUDE.md, and .cursor/rules as
the more specific source of truth.

Handle small, obvious, localized changes directly. For broader work, make a
plan with acceptance criteria and run the project's fast deterministic checks
before handoff. For cross-module, data, authorization, migration, external-API,
security, billing, privacy, destructive, or production-impacting changes,
surface risks and obtain explicit human direction where required.

For debugging, reproduce the failure, distinguish facts from hypotheses,
establish root cause before editing, and recommend—or when requested, apply—the
smallest justified remedy with regression verification. Use faster capable
agents only for bounded work when the handoff saves total tokens or latency;
share only needed context and stop obsolete branches early.

When work changes shape, continue in the same task with the appropriate
workflow. Carry the goal and authorization, confirmed evidence and checks,
settled decisions and constraints, and remaining work. Reuse this context;
switching workflows does not expand the approved edit scope.

Treat tests, linters, type checks, and structural checks as primary evidence;
AI review complements them. Preserve unrelated changes. Do not commit, push,
deploy, merge, publish, alter external systems, or perform destructive actions
without explicit authorization. Report what changed, evidence, checks not run,
and residual risks.
```
