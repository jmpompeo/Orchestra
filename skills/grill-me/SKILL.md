---
name: grill-me
description: Stress-test a non-trivial plan, design, or decision through a structured interview before implementation. Use when the user asks to be grilled, wants to pressure-test their thinking, or needs important design branches resolved; do not use for small, obvious, localized changes.
---

# Grill me

Use this skill before planning or implementing a non-trivial change. This
workflow is adapted from Matt Pocock's `grilling` skill under the MIT license;
see `LICENSE`.

1. Read the repository instructions and relevant project context. Inspect the
   codebase for facts that can answer a question before asking the user.
2. Map the unresolved work as a decision tree. Separate facts to discover from
   decisions that require the user's intent.
3. Work in rounds. In each round, ask every independent decision whose
   prerequisites are settled. Number each question and give a recommended
   answer with a brief rationale. Do not ask a question whose answer depends on
   another open question in the same round.
4. Let each answer update the tree. Explore the repository or delegate focused
   read-only discovery for facts; do not make the user answer questions that
   the available context can resolve.
5. Do not edit code, files, configuration, or external systems during the
   grilling session. The user owns decisions; wait for their answers between
   rounds.
6. When no unresolved decision branches remain, return a decision summary:
   outcome, scope and non-goals, settled choices and rationale, constraints,
   risks, acceptance criteria, and remaining unknowns. Ask the user to confirm
   shared understanding.
7. Only after confirmation, return to the originating workflow: offer to resume
   `$agentic-debugging` with the evidence packet and settled remedy when the
   interview arose from diagnosis; otherwise offer to continue with
   `$agentic-feature-delivery`. Offer to record durable, project-specific
   decisions in `docs/agent-context.md` or recurring process lessons in
   `docs/harness-evolution.md`; never write either without authorization.
