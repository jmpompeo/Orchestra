# AI engineering workflow configuration

`agent-harness` is the only supported installation path for this private,
cross-tool configuration. It is released as a self-contained single binary, so
users need neither a source clone nor a .NET runtime. This repository is for
auditing and maintaining the harness.

## First-time setup

Authenticate GitHub CLI to an account with access to
`jmpompeo/agent-workflow-config`. Download the archive matching your platform,
verify it with the accompanying `SHA256SUMS`, then place the extracted binary
on a user-owned directory already on `PATH` (for example `~/.local/bin`). No
administrator privileges are required.

```sh
gh auth login
gh release download --repo jmpompeo/agent-workflow-config --pattern 'agent-harness-osx-arm64.zip' --pattern SHA256SUMS
shasum -a 256 -c SHA256SUMS
unzip agent-harness-osx-arm64.zip -d "$HOME/.local/bin"
agent-harness install --tools codex --dry-run
agent-harness install --tools codex
```

Available runtime assets are `osx-arm64`, `osx-x64`, `linux-x64`, and `win-x64`.
On Windows, use `Get-FileHash -Algorithm SHA256` to verify the downloaded ZIP,
extract `agent-harness.exe` to a user-owned directory on `PATH`, and run it in
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
For a personal Cursor baseline, run `agent-harness cursor-rules --print` and
paste the result into Cursor Settings → Rules → User Rules.

## Conflicts, backups, and safety

Preview changes first:

```sh
agent-harness install --tools codex,claude --dry-run
```

The CLI creates missing files, updates only unchanged CLI-owned files, and
never silently overwrites a different file. It refuses links/reparse points and
records SHA-256 ownership data in its per-user state directory. To explicitly
replace a conflicting file while retaining a timestamped sibling backup:

```sh
agent-harness install --tools codex --dry-run --backup
agent-harness install --tools codex --backup
```

Existing non-CLI configuration—including configuration previously installed by
an older source-based installer—is treated as unowned. It is preserved even if
its content matches the harness; review the preview and use `--backup` only
when you intentionally want the CLI to take over.

## Updating

```sh
agent-harness update
agent-harness install --tools codex,claude --dry-run
```

`update` downloads the matching private GitHub Release through authenticated
GitHub CLI, verifies the ZIP against `SHA256SUMS`, and replaces only the CLI
binary. It never changes configuration automatically. Review the dry run, then
run `install` if you accept the configuration updates.

## Add the harness to a project

From the target project root:

```sh
agent-harness init-project --tools codex,claude,cursor
agent-harness init-project --tools codex,claude,cursor --apply
```

The first command is preview-only. `--apply` creates missing selected-tool
files only; existing instructions, rules, and docs are conflicts requiring a
manual merge. It does not remove project-local files.

## Work-versus-personal boundaries

- Keep this repository generic: no credentials, customer data, internal
  hostnames, tickets, logs, transcripts, or proprietary procedures.
- Put work-only facts in the relevant work repository only when policy allows.
- Treat a private Git repository as access control, not secret storage.
- Review staged content before committing; `.gitignore` is a guardrail, not a
  secret scanner.

## Change model assignments

Maintainers edit only `models.conf`, then build and release a new binary.
Users run `agent-harness update` and preview their selected installation. The
orchestrator assignment is advisory; explorer, worker, verifier, and reviewer
definitions are rendered from this one file.

## Safe uninstall

```sh
agent-harness uninstall --tools codex,claude --dry-run
agent-harness uninstall --tools codex,claude
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

Pushing a `v*` tag builds self-contained single-file binaries on the matching
macOS, Linux, and Windows runners, produces `SHA256SUMS`, and publishes the
private GitHub Release. Checksums provide download-integrity verification;
Apple notarization and Windows code signing remain deferred until protected
signing identities are available.
