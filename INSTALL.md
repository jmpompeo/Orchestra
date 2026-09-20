# Orchestra

`orchestrate` is the supported installation path for this cross-tool
configuration. It is released as a self-contained single binary, so
users need neither a source clone nor a .NET runtime. This repository is for
auditing and maintaining the harness.

## First-time setup

Authenticate GitHub CLI. Download the archive matching your platform from
`jmpompeo/orchestra`, verify it with the accompanying `SHA256SUMS`, then place
the extracted binary on a user-owned directory already on `PATH` (for example
`~/.local/bin`). No administrator privileges are required.

```sh
gh auth login
gh release download --repo jmpompeo/orchestra --pattern 'orchestrate-osx-arm64.zip' --pattern SHA256SUMS
grep 'orchestrate-osx-arm64.zip$' SHA256SUMS | shasum -a 256 -c -
unzip orchestrate-osx-arm64.zip -d "$HOME/.local/bin"
orchestrate install --tools codex --dry-run
orchestrate install --tools codex
```

Available runtime assets are `osx-arm64`, `osx-x64`, `linux-x64`, and `win-x64`.
On Windows, use `Get-FileHash -Algorithm SHA256` to verify the downloaded ZIP,
extract `orchestrate.exe` to a user-owned directory on `PATH`, and run it in
PowerShell.

Without `--tools`, `install` presents an interactive selector. Automation must
use `--tools codex,claude,cursor` or `--tools all`.

## What the CLI installs

| Tool | Personal installation |
| --- | --- |
| Codex | `~/.codex/AGENTS.md`, `~/.codex/agents/`, and full skills under `~/.agents/skills/` |
| Claude Code | `~/.claude/CLAUDE.md`, `~/.claude/agents/`, and portable skills under `~/.claude/skills/` |
| Cursor | No global files; Cursor rules and generated commands are project-local |

The CLI never installs `project-template/` globally. Cursor commands are
generated from each canonical `SKILL.md`, excluding Codex-only agent metadata.
For a personal Cursor baseline, run `orchestrate cursor-rules --print` and
paste the result into Cursor Settings → Rules → User Rules.

Bundled workflows include `$agentic-debugging` for evidence-driven diagnosis,
root-cause fixes, and regression verification; `$grill-me` for resolving
non-trivial choices after investigation or before feature implementation;
`$agentic-feature-delivery` for executing an approved feature; and
`$bootstrap-agent-harness` for adopting the framework in an existing
repository.

## Conflicts, backups, and safety

Preview changes first:

```sh
orchestrate install --tools codex,claude --dry-run
```

The CLI creates missing files, updates only unchanged CLI-owned files, and
never silently overwrites a different file. It refuses links/reparse points and
records SHA-256 ownership data in its per-user state directory. To explicitly
replace a conflicting file while retaining a timestamped sibling backup:

```sh
orchestrate install --tools codex --dry-run --backup
orchestrate install --tools codex --backup
```

Existing non-CLI configuration—including configuration previously installed by
an older source-based installer—is treated as unowned. It is preserved even if
its content matches the harness; review the preview and use `--backup` only
when you intentionally want the CLI to take over.

## Migrating from agent-harness

Existing `agent-harness` users must manually download and install
`orchestrate`, verify its archive with `SHA256SUMS`, then remove the old
executable from `PATH`. Existing managed-file state is retained: Orchestra
keeps the established internal state identity, so already managed files remain
tracked.

## Updating

```sh
orchestrate update
orchestrate install --tools codex,claude --dry-run
```

`update` downloads the matching GitHub Release through authenticated GitHub
CLI, verifies the ZIP against `SHA256SUMS`, and replaces only the CLI
binary. It never changes configuration automatically. Review the dry run, then
run `install` if you accept the configuration updates.

## Add the harness to a project

From the target project root:

```sh
orchestrate init-project --tools codex,claude,cursor
orchestrate init-project --tools codex,claude,cursor --apply
```

The first command is preview-only. `--apply` creates missing selected-tool
files only; existing instructions, rules, and docs are conflicts requiring a
manual merge. It does not remove project-local files.

## Work-versus-personal boundaries

- Keep this repository generic: no credentials, customer data, internal
  hostnames, tickets, logs, transcripts, or proprietary procedures.
- Put work-only facts in the relevant work repository only when policy allows.
- Treat repository access control as distinct from secret storage.
- Review staged content before committing; `.gitignore` is a guardrail, not a
  secret scanner.

## Change model assignments

Maintainers edit only `models.conf`, then build and release a new binary.
Users run `orchestrate update` and preview their selected installation. The
orchestrator assignment is advisory; explorer, worker, verifier, and reviewer
definitions are rendered from this one file.

## Safe uninstall

```sh
orchestrate uninstall --tools codex,claude --dry-run
orchestrate uninstall --tools codex,claude
```

Only unchanged, CLI-owned global files are removed. Retired skill files are
removed only when their ownership hash still matches. Modified, unknown, or
unsafe files and all project-local harness files are preserved.

## Developing and releasing

Maintainers need the .NET 10 SDK:

```sh
dotnet build AgentHarness.sln --configuration Release
dotnet run --project tests/AgentHarness.Tests/AgentHarness.Tests.csproj --configuration Release
```

Use Conventional Commit messages for changes that should release: `feat:` for a
minor version, `fix:` for a patch, and `feat!:` or `fix!:` for a major version.
After merged changes reach `main`, Release Please opens or updates a release
PR. Merging that PR creates the version tag and GitHub Release; the
workflow then builds self-contained single-file binaries on the matching macOS,
Linux, and Windows runners and uploads `SHA256SUMS`. No manual tag creation is
required. Checksums provide download-integrity verification; Apple notarization
and Windows code signing remain deferred until protected signing identities are
available.

If an existing release is missing or has corrupt assets, open **Actions →
Release Orchestra → Run workflow**, enter its existing tag (for example
`v1.0.0`), and run it. The recovery path validates that the release exists,
rebuilds all platform assets from that tag, and replaces only the release
archives and checksum manifest. It does not create a new version or tag.
