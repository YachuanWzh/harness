#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const { existsSync, readFileSync } = require("node:fs");
const { dirname, join, resolve, sep } = require("node:path");

const packageRoot = resolve(dirname(__filename), "..");

function fail(message) {
  console.error(`superharness: ${message}`);
  process.exit(1);
}

function parseArguments(argv) {
  const forwarded = [];
  let targetDir = process.cwd();
  let host;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "init") continue;
    if (argument === "--target-dir" || argument === "--cwd" || argument === "-C") {
      const value = argv[index + 1];
      if (!value) fail(`${argument} requires a directory`);
      targetDir = resolve(value);
      index += 1;
      continue;
    }
    if (argument.startsWith("--target-dir=")) {
      targetDir = resolve(argument.slice("--target-dir=".length));
      continue;
    }
    if (argument.startsWith("--cwd=")) {
      targetDir = resolve(argument.slice("--cwd=".length));
      continue;
    }
    if (argument === "--flavor" || argument === "--claude" || argument === "--both") {
      host = argument.slice(2);
      continue;
    }
    if (argument === "--host") {
      const value = argv[index + 1];
      if (!value) fail("--host requires auto, flavor, claude, or both");
      host = value.toLowerCase();
      index += 1;
      continue;
    }
    if (argument.startsWith("--host=")) {
      host = argument.slice("--host=".length).toLowerCase();
      continue;
    }
    forwarded.push(argument);
  }

  if (host && !["auto", "flavor", "claude", "both"].includes(host)) {
    fail(`unsupported host ${host}; expected auto, flavor, claude, or both`);
  }
  if (host && host !== "auto") forwarded.push(`--${host}`);
  return { targetDir, forwarded };
}

function runInstaller(argv) {
  const { targetDir, forwarded } = parseArguments(argv);
  if (!existsSync(targetDir)) fail(`target directory not found: ${targetDir}`);

  if (process.platform === "win32") {
    const installer = join(packageRoot, "lib", "install.ps1");
    if (!existsSync(installer)) fail(`installer not found: ${installer}`);
    return spawnSync("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", installer,
      "-TargetDir", targetDir, ...forwarded,
    ], { stdio: "inherit", windowsHide: true }).status ?? 1;
  }

  const installer = join(packageRoot, "lib", "install.sh");
  if (!existsSync(installer)) fail(`installer not found: ${installer}`);
  return spawnSync("bash", [installer, "--target-dir", targetDir, ...forwarded], {
    stdio: "inherit",
  }).status ?? 1;
}

function selfUpdate() {
  const packagePath = join(packageRoot, "package.json");
  let packageName = "@flavor-code/superharness";
  try {
    packageName = JSON.parse(readFileSync(packagePath, "utf8")).name || packageName;
  } catch {
    // The published package always has package.json; retain the public name as a safe fallback.
  }
  const npm = process.platform === "win32" ? "npm.cmd" : "npm";
  const segments = packageRoot.split(sep);
  const nodeModulesIndex = segments.lastIndexOf("node_modules");
  const prefix = nodeModulesIndex > 0 ? segments.slice(0, nodeModulesIndex).join(sep) : undefined;
  const installArgs = ["install", "--global", ...(prefix ? ["--prefix", prefix] : []), `${packageName}@latest`, "--ignore-scripts"];
  return spawnSync(npm, installArgs, {
    stdio: "inherit",
    shell: process.platform === "win32",
    windowsHide: true,
  }).status ?? 1;
}

const args = process.argv.slice(2);
process.exit(args.includes("self-update") || args.includes("--self-update")
  ? selfUpdate()
  : runInstaller(args));
