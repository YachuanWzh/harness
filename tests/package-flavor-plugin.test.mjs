import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPT = join(REPO_ROOT, "package-flavor-plugin.ps1");

test("package script syncs the Flavor version and creates a complete tgz", () => {
  const fixture = mkdtempSync(join(tmpdir(), "superharness-package-fixture-"));
  const output = join(fixture, "release");
  const source = join(fixture, "template", "plugins", "superharness");
  try {
    mkdirSync(join(source, ".claude-plugin"), { recursive: true });
    mkdirSync(join(source, "plugin"), { recursive: true });
    mkdirSync(join(source, "skills", "go"), { recursive: true });
    mkdirSync(join(source, "scripts"), { recursive: true });
    writeFileSync(join(source, ".claude-plugin", "plugin.json"), JSON.stringify({ name: "superharness", version: "9.8.7" }));
    writeFileSync(join(source, "plugin", "flavor-plugin.json"), JSON.stringify({
      name: "superharness", version: "0.0.1", apiVersion: "1", main: "./index.js", permissions: [],
      contributes: { commands: [], tools: [], hooks: [], skillRoots: [{ name: "superharness", path: "./skills" }], modelAdapters: [] },
    }, null, 2));
    writeFileSync(join(source, "plugin", "index.js"), "export function activate() {}\n");
    writeFileSync(join(source, "HARNESS.md"), "# Harness\n");
    writeFileSync(join(source, "skills", "go", "SKILL.md"), "# Go\n");
    writeFileSync(join(source, "scripts", "ralph-lib.ps1"), "# ps\n");
    writeFileSync(join(source, "scripts", "ralph-lib.sh"), "# sh\n");

    const result = spawnSync("powershell", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPT,
      "-RepositoryRoot", fixture, "-OutputDirectory", output, "-SkipTests",
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const flavor = JSON.parse(readFileSync(join(source, "plugin", "flavor-plugin.json"), "utf8"));
    assert.equal(flavor.version, "9.8.7");

    const stage = join(output, "superharness-9.8.7");
    const archive = join(output, "superharness-9.8.7.tgz");
    const listing = spawnSync("tar.exe", ["-tzf", archive], { encoding: "utf8" });
    assert.equal(listing.status, 0, listing.stderr);
    const files = listing.stdout.split(/\r?\n/).map((value) => value.replace(/^\.\//, ""));
    for (const required of ["flavor-plugin.json", "index.js", "HARNESS.md", "skills/go/SKILL.md", "scripts/ralph-lib.ps1", "scripts/ralph-lib.sh"]) {
      assert.ok(files.includes(required), `archive missing ${required}`);
    }
    assert.equal(JSON.parse(readFileSync(join(stage, "flavor-plugin.json"), "utf8")).version, "9.8.7");
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});
