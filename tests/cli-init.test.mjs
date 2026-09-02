import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CLI = join(REPO_ROOT, "bin", "superharness.cjs");
const BASH_INSTALLER = join(REPO_ROOT, "lib", "install.sh");

function initialize(host) {
  const project = mkdtempSync(join(tmpdir(), `superharness-${host}-`));
  const result = spawnSync(process.execPath, [CLI, "init", `--host=${host}`, "--target-dir", project], { encoding: "utf8" });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return project;
}

test("cross-platform npm CLI initializes Flavor explicitly with current release notes", () => {
  const project = initialize("flavor");
  try {
    const flavor = readFileSync(join(project, "FLAVOR.md"), "utf8");
    assert.match(flavor, /SUPERHARNESS:FLAVOR-BEGIN/);
    assert.match(flavor, /Latest update \(v1\.1\.2\)/);
    assert.doesNotMatch(flavor, /SUPERHARNESS:BEGIN -->/);
  } finally { rmSync(project, { recursive: true, force: true }); }
});

test("cross-platform npm CLI can initialize both hosts", () => {
  const project = initialize("both");
  try {
    assert.match(readFileSync(join(project, "FLAVOR.md"), "utf8"), /Latest update \(v1\.1\.2\)/);
    assert.match(readFileSync(join(project, "CLAUDE.md"), "utf8"), /Latest update \(v1\.1\.2\)/);
  } finally { rmSync(project, { recursive: true, force: true }); }
});

test("bash installer avoids heredoc command substitution rejected by macOS Bash 3.2", () => {
  const installer = readFileSync(BASH_INSTALLER, "utf8");
  assert.doesNotMatch(
    installer,
    /CLAUDE_SECTION="\$\(cat <<'/,
    "Bash 3.2 misparses apostrophes inside a quoted heredoc nested in command substitution",
  );
});
