---
name: agentic-feature-delivery
description: Plan, delegate, implement, verify, and review a non-trivial software feature end-to-end. Use for ambiguous or cross-cutting implementation work; skip for small localized edits or read-only advice.
---

# Agentic feature delivery

Own the complete integrated result in one orchestrated session.

1. Read repository instructions and `docs/agent-context.md` when present.
   Read `docs/harness-evolution.md` when it exists and a recurring failure is
   relevant. Inspect the working tree and preserve unrelated changes.
2. Decide whether orchestration is justified. Handle a small, obvious,
   localized edit directly without subagents.
3. Resolve meaningful ambiguity before editing. Establish outcomes,
   constraints, non-goals, edge cases, and acceptance criteria. Ask only about
   decisions that materially change behavior, architecture, risk, cost, or
   destructive scope.
4. Assign a risk tier: localized, module-level, cross-cutting, or
   high-consequence. For high-consequence work, obtain explicit human
   acceptance criteria before changing security, billing, privacy, destructive,
   or production-impacting behaviour.
5. Explore actual code paths and tests. Delegate focused read-only questions
   when this protects the parent context or materially reduces latency.
6. Build a dependency-aware task graph. Every delegated task must state its
   goal, acceptance criteria, owned scope or files, relevant context,
   constraints, validation command, and return contract.
7. Parallelize only independent work. Parallel writers must have explicit,
   non-overlapping file ownership. Never overlap shared migration, schema, or
   integration surfaces.
8. Keep architecture and integration decisions with the parent. Inspect every
   returned change and the final diff; subagent reports are not proof.
9. Run fast deterministic checks before handoff, then the broader checks the
   risk tier requires before integration. Use tests, linters, type checks, and
   structural checks as primary feedback; model review complements them.
   Separate new failures from pre-existing or environmental failures.
10. For behaviour-critical work, use approved fixtures or explicit manual
    acceptance steps. Do not treat agent-authored tests alone as sufficient
    evidence when trusted examples are available.
11. For non-trivial changes, obtain an independent read-only review, address
   material findings, and rerun affected checks.
12. When a pattern has failed at least twice, propose the smallest durable
    control in `docs/harness-evolution.md`; never record sensitive data or raw
    transcripts. Stop only when acceptance criteria are met or a concrete
    blocker remains.

Do not commit unless the user requests it. Never push, deploy, merge, publish,
modify external systems, or perform destructive actions unless the user
explicitly authorizes the exact action.

Return one handoff containing the outcome, risk tier, decisions and assumptions,
files changed, deterministic and behavioural evidence, review findings, checks
not run with reasons, unresolved risks or blockers, and required user action.
