using AgentHarness;
using System.Security.Cryptography;
using System.Text.Json;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception("FAILED: " + message);
}

var parsed = ToolSelection.Parse("codex, cursor");
Check(parsed == (Tool.Codex | Tool.Cursor), "tool selection parses comma-separated values");
Check(ToolSelection.Parse("all") == Tool.All, "all selects every tool");
var cursor = CursorCommandGenerator.FromSkill("demo", "---\nname: demo\n---\n\n# Workflow\n\nDo work.");
Check(!cursor.Contains("name: demo", StringComparison.Ordinal), "Cursor command excludes skill front matter");
Check(cursor.Contains("Do work.", StringComparison.Ordinal), "Cursor command retains skill body");
var sums = ChecksumParser.Parse(new string('a', 64) + "  agent-harness-osx-arm64.zip\n");
Check(sums["agent-harness-osx-arm64.zip"] == new string('a', 64), "checksum parser reads a valid manifest");

var root = Path.Combine(Path.GetTempPath(), "agent-harness-tests-" + Guid.NewGuid().ToString("N"));
var home = Path.Combine(root, "home"); var state = Path.Combine(root, "state"); var project = Path.Combine(root, "project");
try
{
    var app = new HarnessApp(home, state);
    Check(app.Run(new[] { "install", "--tools", "codex" }) == 0, "Codex install succeeds in isolated home");
    Check(File.Exists(Path.Combine(home, ".codex", "AGENTS.md")), "Codex instructions installed");
    Check(File.Exists(Path.Combine(home, ".agents", "skills", "agentic-feature-delivery", "SKILL.md")), "Codex skill installed");
    Check(app.Run(new[] { "install", "--tools", "codex" }) == 0, "repeat install is a no-op");
    var instructions = Path.Combine(home, ".codex", "AGENTS.md");
    File.WriteAllText(instructions, "personal change");
    Check(app.Run(new[] { "install", "--tools", "codex" }) == 0, "modified file conflict is non-destructive");
    Check(File.ReadAllText(instructions) == "personal change", "conflict preserves user configuration");
    Check(app.Run(new[] { "install", "--tools", "codex", "--backup" }) == 0, "explicit backup replacement succeeds");
    Check(File.ReadAllText(instructions).Contains("Personal engineering workflow", StringComparison.Ordinal), "backup replacement installs managed content");
    Check(Directory.GetFiles(Path.Combine(home, ".codex"), "AGENTS.md.backup.*").Length == 1, "backup is retained");
    var stale = Path.Combine(home, ".agents", "skills", "retired", "SKILL.md"); Directory.CreateDirectory(Path.GetDirectoryName(stale)!); File.WriteAllText(stale, "retired");
    var statePath = Path.Combine(state, "state.json"); var document = JsonSerializer.Deserialize<StateDocument>(File.ReadAllText(statePath))!;
    document.Files[Path.GetFullPath(stale)] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(stale))).ToLowerInvariant();
    File.WriteAllText(statePath, JsonSerializer.Serialize(document));
    Check(app.Run(new[] { "install", "--tools", "codex" }) == 0 && !File.Exists(stale), "stale unchanged skill is reconciled");
    var before = Directory.Exists(home) ? Directory.GetFiles(home, "*", SearchOption.AllDirectories).Length : 0;
    Check(app.Run(new[] { "install", "--tools", "claude", "--dry-run" }) == 0, "dry run succeeds");
    Check(Directory.GetFiles(home, "*", SearchOption.AllDirectories).Length == before, "dry run does not create Claude files");
    Directory.CreateDirectory(project); var previous = Directory.GetCurrentDirectory(); Directory.SetCurrentDirectory(project);
    try
    {
        Check(app.Run(new[] { "init-project", "--tools", "cursor" }) == 0, "project preview succeeds");
        Check(!Directory.Exists(Path.Combine(project, ".cursor")), "project preview does not write");
        Check(app.Run(new[] { "init-project", "--tools", "cursor", "--apply" }) == 0, "Cursor project apply succeeds");
        Check(File.Exists(Path.Combine(project, ".cursor", "commands", "agentic-feature-delivery.md")), "Cursor command generated");
    }
    finally { Directory.SetCurrentDirectory(previous); }
    Check(app.Run(new[] { "uninstall", "--tools", "codex" }) == 0, "uninstall succeeds");
    Check(!File.Exists(Path.Combine(home, ".codex", "AGENTS.md")), "uninstall removes unchanged owned file");
    var legacyHome = Path.Combine(root, "legacy-home"); var legacyState = Path.Combine(root, "legacy-state");
    var legacyInstructions = Path.Combine(legacyHome, ".codex", "AGENTS.md"); Directory.CreateDirectory(Path.GetDirectoryName(legacyInstructions)!);
    File.WriteAllBytes(legacyInstructions, new AssetStore().ReadBytes("global/codex/AGENTS.md"));
    var legacy = new HarnessApp(legacyHome, legacyState);
    Check(legacy.Run(new[] { "install", "--tools", "codex" }) == 0, "legacy-shaped install is reported without taking ownership");
    Check(legacy.Run(new[] { "uninstall", "--tools", "codex" }) == 0, "legacy-shaped uninstall succeeds");
    Check(File.Exists(legacyInstructions), "matching unowned legacy configuration is preserved");
    Console.WriteLine("All agent-harness tests passed.");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, true);
}
