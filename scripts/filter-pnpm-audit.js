#!/usr/bin/env node
/**
 * Filter pnpm audit JSON output through .github/audit-exceptions.json.
 *
 * The exceptions file lists advisories with NO patched release available —
 * the high+ gate cannot go green on them until upstream ships a fix, and a
 * permanently-red gate teaches red-ignoring. Entries need a reason and a
 * review date; the file's own comment forbids excepting anything that has
 * a patched version.
 *
 * Usage: node filter-pnpm-audit.js <audit.json> [exceptions.json]
 * Exit 0 = no non-excepted high+/critical findings; exit 1 = findings remain.
 */
const fs = require("node:fs");

const auditPath = process.argv[2] ?? "audit.json";
const exceptionsPath = process.argv[3] ?? "../.github/audit-exceptions.json";

const audit = JSON.parse(fs.readFileSync(auditPath, "utf8"));
const exceptions = JSON.parse(fs.readFileSync(exceptionsPath, "utf8"));
const excepted = new Map(
  exceptions.exceptions.map((e) => [`${e.module}@${e.advisory}`, e.reason]),
);

const BLOCKING = new Set(["high", "critical"]);
const remaining = [];
for (const adv of Object.values(audit.advisories ?? {})) {
  if (!BLOCKING.has(adv.severity)) continue;
  const key = `${adv.module_name}@${adv.url.split("/").pop()}`;
  if (excepted.has(key)) {
    console.log(`audit-exception: ${key} — ${excepted.get(key).slice(0, 80)}…`);
    continue;
  }
  remaining.push(`${adv.severity} ${adv.module_name} ${adv.url}`);
}

if (remaining.length > 0) {
  console.error(`audit: ${remaining.length} blocking finding(s) remain:`);
  for (const r of remaining) console.error(`  ${r}`);
  process.exit(1);
}
console.log("audit: PASS (high+; exceptions applied)");
