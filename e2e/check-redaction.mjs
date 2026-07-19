#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const [canaryPath, ...diagnosticPaths] = process.argv.slice(2);
if (!canaryPath || diagnosticPaths.length === 0) {
  process.stderr.write("usage: check-redaction.mjs <canaries.jsonl> <diagnostic>...\n");
  process.exit(2);
}

const canaryLines = (await readFile(canaryPath, "utf8"))
  .split("\n")
  .filter((line) => line.trim().length > 0);
if (canaryLines.length === 0) {
  process.stderr.write("redaction check failed: no canaries were registered\n");
  process.exit(1);
}

const canaries = canaryLines.map((line) => JSON.parse(line));
const diagnostics = (await Promise.all(
  diagnosticPaths.map((path) => readFile(path, "utf8")),
)).join("\n");

let leaked = false;
for (const { label, value } of canaries) {
  if (typeof label !== "string" || typeof value !== "string" || value.length < 8) {
    process.stderr.write("redaction check failed: malformed canary entry\n");
    process.exit(1);
  }
  if (!diagnostics.includes(value)) continue;
  leaked = true;
  const fingerprint = createHash("sha256").update(value).digest("hex").slice(0, 12);
  process.stderr.write(
    `redaction canary leaked label=${label} fingerprint=sha256:${fingerprint}\n`,
  );
}

if (leaked) process.exit(1);
process.stdout.write(`redaction canaries passed (${canaries.length} values)\n`);
