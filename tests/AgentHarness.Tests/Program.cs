using AgentHarness;
using System.Security.Cryptography;
using System.Text.Json;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception("FAILED: " + message);
}

static (int ExitCode, string Output, string Error) Capture(HarnessApp app, string[] args)
{
    var previousOutput = Console.Out;
    var previousError = Console.Error;
    using var output = new StringWriter();
    using var error = new StringWriter();
    try
    {
        Console.SetOut(output);
        Console.SetError(error);
        var exitCode = app.Run(args);
        return (exitCode, output.ToString(), error.ToString());
    }
    finally
    {
        Console.SetOut(previousOutput);
        Console.SetError(previousError);
    }
}

var parsed = ToolSelection.Parse("codex, cursor");
Check(parsed == (Tool.Codex | Tool.Cursor), "tool selection parses comma-separated values");
Check(ToolSelection.Parse("all") == Tool.All, "all selects every tool");
var cursor = CursorCommandGenerator.FromSkill("demo", "---\nname: demo\n---\n\n# Workflow\n\nDo work.");
Check(!cursor.Contains("name: demo", StringComparison.Ordinal), "Cursor command excludes skill front matter");
Check(cursor.Contains("Do work.", StringComparison.Ordinal), "Cursor command retains skill body");
var sums = ChecksumParser.Parse(new string('a', 64) + "  orchestrate-osx-arm64.zip\n");
Check(sums["orchestrate-osx-arm64.zip"] == new string('a', 64), "checksum parser reads a valid manifest");

var root = Path.Combine(Path.GetTempPath(), "orchestra-tests-" + Guid.NewGuid().ToString("N"));
var home = Path.Combine(root, "home"); var state = Path.Combine(root, "state"); var project = Path.Combine(root, "project");
try
{
    var app = new HarnessApp(home, state);
    var help = Capture(app, new[] { "--help" });
    Check(help.ExitCode == 0 && help.Output.Contains("orchestrate", StringComparison.Ordinal), "help uses the orchestrate command name");
    Check(!help.Output.Contains("agent-harness", StringComparison.Ordinal), "help omits the retired command name");
    var unknown = Capture(app, new[] { "unknown-command" });
    Check(unknown.ExitCode == 2 && unknown.Error.Contains("orchestrate --help", StringComparison.Ordinal), "unknown-command guidance uses orchestrate");
    var previousStateHome = Environment.GetEnvironmentVariable("AGENT_HARNESS_STATE_HOME");
    var compatibleStateHome = Path.Combine(root, "compatible-state");
    try
    {
        Environment.SetEnvironmentVariable("AGENT_HARNESS_STATE_HOME", compatibleStateHome);
        var compatibleStatus = Capture(new HarnessApp(home), new[] { "status" });
        Check(compatibleStatus.Output.Contains(Path.Combine(compatibleStateHome, "state.json"), StringComparison.Ordinal), "legacy state-home override remains supported");
    }
    finally { Environment.SetEnvironmentVariable("AGENT_HARNESS_STATE_HOME", previousStateHome); }
    if (!OperatingSystem.IsWindows())
    {
        var previousXdgStateHome = Environment.GetEnvironmentVariable("XDG_STATE_HOME");
        var xdgStateHome = Path.Combine(root, "xdg-state");
        try
        {
            Environment.SetEnvironmentVariable("XDG_STATE_HOME", xdgStateHome);
            var compatibleStatus = Capture(new HarnessApp(home), new[] { "status" });
            Check(compatibleStatus.Output.Contains(Path.Combine(xdgStateHome, "agent-harness", "state.json"), StringComparison.Ordinal), "legacy default state identity remains supported");
        }
        finally { Environment.SetEnvironmentVariable("XDG_STATE_HOME", previousXdgStateHome); }
    }
    Check(app.Run(new[] { "install", "--tools", "codex" }) == 0, "Codex install succeeds in isolated home");
    Check(File.Exists(Path.Combine(home, ".codex", "AGENTS.md")), "Codex instructions installed");
    Check(File.Exists(Path.Combine(home, ".agents", "skills", "agentic-feature-delivery", "SKILL.md")), "Codex skill installed");
    Check(File.Exists(Path.Combine(home, ".agents", "skills", "grill-me", "SKILL.md")), "grill-me skill installed");
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
        Check(File.Exists(Path.Combine(project, ".cursor", "commands", "grill-me.md")), "Cursor grill-me command generated");
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
    Console.WriteLine("All Orchestra tests passed.");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, true);
}
