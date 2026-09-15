---
name: bootstrap-agent-harness
description: Inspect a software repository and draft a project-specific agentic harness with factual context, risk tiers, validation sensors, and safe behaviour fixtures. Use when adopting this workflow in a new project or when the existing agent context is incomplete.
---

# Bootstrap agent harness

Build an evidence-backed draft before changing project instructions. Default to
read-only discovery; write or merge template files only when the user authorizes
the specific project changes.

1. Read existing repository instructions, CI configuration, build manifests,
   scripts, test directories, formatters, linters, type-checkers, and relevant
   architecture documents. Preserve unrelated work.
2. Inventory only facts supported by the repository. Record unknown commands,
   boundaries, and policies as unknown rather than inventing them.
3. Draft `docs/agent-context.md` from the project template: product boundary,
   architecture map, real commands, safety constraints, validation sensors, and
   definition of done.
4. Classify available feedback into fast deterministic checks, broader
   integration checks, architecture constraints, and behaviour evidence. Flag
   missing sensors as recommendations, not completed controls.
5. Propose risk tiers appropriate to the repository. Require explicit human
   acceptance criteria for security, billing, privacy, destructive, or
   production-impacting behaviour.
6. Identify behaviour where approved fixtures would provide stronger evidence
   than agent-authored tests alone. Never copy secrets, production personal data,
   or internal material into a fixture.
7. Draft `docs/harness-evolution.md` only as a sanitized mechanism for recurring
   failures. Do not convert a single incident, raw transcript, or temporary
   preference into a permanent rule.
8. Return the proposed files, the evidence for every populated field, unknowns,
   missing sensors, and exact human decisions required before writing.
