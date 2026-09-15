# Agent context

Keep this file concise and factual. Replace bracketed text, then remove this
sentence. Never add credentials, secrets, personal data, internal-only URLs, or
other information that is not approved for this repository.

## Product and boundaries

- Purpose: [one sentence]
- In scope: [primary applications or services]
- Out of scope: [systems agents must not modify]
- Work/personal boundary: [what may not cross environments]

## Architecture map

- Entry points: [paths]
- Core domains/modules: [paths and responsibilities]
- Data stores/external services: [names and boundaries]
- Existing patterns to copy: [representative paths]

## Commands

- Install: `[command]`
- Fast targeted test: `[command]`
- Full test: `[command]`
- Lint/format/type-check: `[commands]`
- Build: `[command]`
- Run locally: `[command]`

## Sensors and validation tiers

Use these as evidence, not as a checklist to fabricate. Leave an item marked
unknown until a maintainer supplies the real command or constraint.

### Fast: run before handoff

- Format: `[command]`
- Type-check/static analysis: `[command]`
- Fast targeted test: `[command]`
- Security or dependency check: `[command or not applicable]`

### Full: run before integration when risk warrants it

- Full test suite: `[command]`
- Build/package: `[command]`
- Integration, end-to-end, or contract test: `[command or not applicable]`

### Architecture and behaviour

- Allowed dependency directions or module boundaries: `[constraints/check]`
- Forbidden imports, coupling, or generated-file edits: `[constraints/check]`
- Approved fixtures or acceptance examples: `[path or not applicable]`
- Manual acceptance steps: `[steps or not applicable]`

## Engineering constraints

- Runtime/toolchain versions: [versions or source-of-truth files]
- Required conventions: [only non-obvious rules]
- Dependency policy: [approval or package-manager rules]
- Compatibility/migration policy: [constraints]
- Generated files: [how they are produced; do not hand-edit]

## Definition of done

- [observable behavior]
- [required automated checks]
- [documentation, telemetry, or migration expectations]

## Evidence handoff

- Deterministic checks: [command, pass/fail, concise evidence]
- Behaviour evidence: [fixture, acceptance example, or manual result]
- Independent review: [required? findings and disposition]
- Not run: [check and reason]

## Safety and delivery

- Secrets/PII: [handling constraints]
- External environments: [what requires explicit approval]
- Branch/commit/PR policy: [rules]
