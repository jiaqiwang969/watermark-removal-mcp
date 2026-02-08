#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import https from "node:https";
import { spawn, spawnSync } from "node:child_process";
import { pipeline } from "node:stream/promises";
import { createWriteStream } from "node:fs";

import AdmZip from "adm-zip";
import * as tar from "tar";

const repo = process.env.WATERMARK_MCP_GITHUB_REPO || "jiaqiwang969/watermark-removal-mcp";
const version = process.env.WATERMARK_MCP_VERSION || "latest";
const binBaseName = process.platform === "win32" ? "watermark-remover-mcp-server.exe" : "watermark-remover-mcp-server";
const cacheBase =
  process.env.WATERMARK_MCP_CACHE_DIR ||
  (process.platform === "win32"
    ? path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "watermark-removal-mcp")
    : path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "watermark-removal-mcp"));

function mapTarget() {
  const archMap = {
    x64: "x86_64",
    arm64: "aarch64",
  };
  const arch = archMap[process.arch];
  if (!arch) {
    throw new Error(`Unsupported architecture: ${process.arch}`);
  }

  if (process.platform === "darwin") {
    return { triple: `${arch}-apple-darwin`, archive: "tar.gz" };
  }
  if (process.platform === "linux") {
    if (arch === "aarch64") {
      throw new Error("Linux aarch64 prebuilt binary is not published yet.");
    }
    return { triple: `${arch}-unknown-linux-gnu`, archive: "tar.gz" };
  }
  if (process.platform === "win32") {
    if (arch !== "x86_64") {
      throw new Error("Windows prebuilt binary is currently only published for x86_64.");
    }
    return { triple: "x86_64-pc-windows-msvc", archive: "zip" };
  }
  throw new Error(`Unsupported platform: ${process.platform}`);
}

function releaseUrl(assetName) {
  if (version === "latest") {
    return `https://github.com/${repo}/releases/latest/download/${assetName}`;
  }
  const normalizedVersion = version.startsWith("v") ? version : `v${version}`;
  return `https://github.com/${repo}/releases/download/${normalizedVersion}/${assetName}`;
}

async function download(url, outputPath) {
  await new Promise((resolve, reject) => {
    const request = https.get(url, (response) => {
      if (
        response.statusCode &&
        response.statusCode >= 300 &&
        response.statusCode < 400 &&
        response.headers.location
      ) {
        response.resume();
        download(response.headers.location, outputPath).then(resolve).catch(reject);
        return;
      }

      if (response.statusCode !== 200) {
        reject(new Error(`Download failed: ${url} (status ${response.statusCode})`));
        response.resume();
        return;
      }

      pipeline(response, createWriteStream(outputPath)).then(resolve).catch(reject);
    });
    request.on("error", reject);
  });
}

async function ensurePrebuiltInstalled() {
  const { triple, archive } = mapTarget();
  const installDir = path.join(cacheBase, version, triple);
  const binPath = path.join(installDir, "bin", binBaseName);
  if (fs.existsSync(binPath)) {
    return { installDir, binPath };
  }

  fs.mkdirSync(installDir, { recursive: true });
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "watermark-mcp-"));
  const assetName = `watermark-remover-mcp-${triple}.${archive}`;
  const archivePath = path.join(tmpRoot, `asset.${archive}`);

  try {
    await download(releaseUrl(assetName), archivePath);
    const unpackDir = path.join(tmpRoot, "unpack");
    fs.mkdirSync(unpackDir, { recursive: true });

    if (archive === "tar.gz") {
      await tar.x({ file: archivePath, cwd: unpackDir });
    } else {
      const zip = new AdmZip(archivePath);
      zip.extractAllTo(unpackDir, true);
    }

    const topLevelDirs = fs
      .readdirSync(unpackDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => path.join(unpackDir, entry.name));
    if (topLevelDirs.length === 0) {
      throw new Error("Downloaded archive did not contain a payload directory.");
    }

    fs.cpSync(topLevelDirs[0], installDir, { recursive: true, force: true });
    if (process.platform !== "win32" && fs.existsSync(binPath)) {
      fs.chmodSync(binPath, 0o755);
    }
    if (!fs.existsSync(binPath)) {
      throw new Error(`Binary not found after extraction: ${binPath}`);
    }
    return { installDir, binPath };
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
}

function resolveScriptsDir(installDir) {
  if (process.env.WATERMARK_SCRIPTS_DIR) {
    return process.env.WATERMARK_SCRIPTS_DIR;
  }

  const bundledScripts = path.join(installDir, "scripts");
  if (fs.existsSync(bundledScripts)) {
    return bundledScripts;
  }

  throw new Error("Cannot find scripts directory. Set WATERMARK_SCRIPTS_DIR explicitly.");
}

function detectPython() {
  const candidates = [];
  if (process.env.WATERMARK_PYTHON_BIN) {
    candidates.push(process.env.WATERMARK_PYTHON_BIN);
  }
  if (process.platform === "win32") {
    candidates.push("python", "python3");
  } else {
    candidates.push("python3", "python");
  }

  for (const cmd of candidates) {
    const result = spawnSync(cmd, ["--version"], { stdio: "ignore" });
    if (result.status === 0) {
      return cmd;
    }
  }
  throw new Error(
    "Python runtime not found. Install Python 3.10+ or set WATERMARK_PYTHON_BIN to your python executable."
  );
}

function ensurePythonDeps(pythonCmd, scriptsDir) {
  if (process.env.WATERMARK_MCP_SKIP_PYTHON_BOOTSTRAP === "1") {
    return;
  }

  const check = spawnSync(
    pythonCmd,
    ["-c", "import pdf2image, img2pdf, cv2, numpy, PIL"],
    { stdio: "ignore" }
  );
  if (check.status === 0) {
    return;
  }

  if (process.env.WATERMARK_MCP_AUTO_INSTALL_PYTHON === "0") {
    throw new Error(
      "Missing Python dependencies. Install with: pip install -r scripts/requirements.txt"
    );
  }

  const requirements = path.join(scriptsDir, "requirements.txt");
  if (!fs.existsSync(requirements)) {
    throw new Error(`requirements.txt not found: ${requirements}`);
  }

  const install = spawnSync(
    pythonCmd,
    ["-m", "pip", "install", "--user", "-r", requirements],
    { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8" }
  );
  if (install.stdout) {
    process.stderr.write(install.stdout);
  }
  if (install.stderr) {
    process.stderr.write(install.stderr);
  }
  if (install.status !== 0) {
    throw new Error("Failed to install Python dependencies.");
  }
}

async function run() {
  const { installDir, binPath } = await ensurePrebuiltInstalled();
  const scriptsDir = resolveScriptsDir(installDir);
  const pythonCmd = detectPython();
  ensurePythonDeps(pythonCmd, scriptsDir);
  const env = { ...process.env, WATERMARK_SCRIPTS_DIR: scriptsDir };
  const child = spawn(binPath, [], { stdio: "inherit", env });

  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 1);
  });
  child.on("error", (error) => {
    console.error(`[watermark-removal-mcp] failed to start binary: ${error.message}`);
    process.exit(1);
  });
}

run().catch((error) => {
  console.error(`[watermark-removal-mcp] ${error.message}`);
  process.exit(1);
});
