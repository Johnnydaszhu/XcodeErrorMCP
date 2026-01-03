#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const packageRoot = path.resolve(__dirname, '..');
const binaryPath = path.join(packageRoot, '.build', 'release', 'xcode-error-mcp');
const swiftpmRoot = path.join(packageRoot, '.build', 'swiftpm');
const cachePath = path.join(swiftpmRoot, 'cache');
const configPath = path.join(swiftpmRoot, 'config');
const securityPath = path.join(swiftpmRoot, 'security');
const clangModuleCachePath = path.join(swiftpmRoot, 'clang-module-cache');

function fileExists(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, options) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  return result.status ?? 1;
}

function main() {
  if (process.platform !== 'darwin') {
    process.stderr.write('xcode-error-mcp only supports macOS (darwin).\n');
    process.exit(1);
  }

  if (process.env.XCODE_ERROR_MCP_SKIP_BUILD === '1') {
    process.stderr.write('Skipping Swift build (XCODE_ERROR_MCP_SKIP_BUILD=1).\n');
    process.exit(0);
  }

  const swiftCheck = spawnSync('swift', ['--version'], { stdio: 'ignore' });
  if (swiftCheck.error || swiftCheck.status !== 0) {
    process.stderr.write('Swift toolchain not found. Install Xcode and ensure `swift` is on PATH.\n');
    process.exit(1);
  }

  fs.mkdirSync(cachePath, { recursive: true });
  fs.mkdirSync(configPath, { recursive: true });
  fs.mkdirSync(securityPath, { recursive: true });
  fs.mkdirSync(clangModuleCachePath, { recursive: true });

  const baseArgs = [
    'build',
    '-c',
    'release',
    '--product',
    'xcode-error-mcp',
    '--cache-path',
    cachePath,
    '--config-path',
    configPath,
    '--security-path',
    securityPath,
    '--manifest-cache',
    'local'
  ];

  const env = { ...process.env, CLANG_MODULE_CACHE_PATH: clangModuleCachePath };
  let status = run('swift', baseArgs, { cwd: packageRoot, env });
  if (status !== 0) {
    process.stderr.write('swift build failed; retrying with --disable-sandbox...\n');
    status = run('swift', [...baseArgs, '--disable-sandbox'], { cwd: packageRoot, env });
  }
  if (status !== 0) process.exit(status);

  if (!fileExists(binaryPath)) {
    process.stderr.write(`Build finished, but binary not found at: ${binaryPath}\n`);
    process.exit(1);
  }
}

main();
