import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { Buffer } from "node:buffer";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

interface ManifestFamily {
  id: string;
  transport: string;
  schema: string;
  description: string;
}

interface Manifest {
  families: ManifestFamily[];
}

const protocolRoot = fileURLToPath(new URL("..", import.meta.url));
const schemaRoot = join(protocolRoot, "schema");
const fixturesRoot = join(protocolRoot, "fixtures");

const fixtureTargets: Record<string, string[]> = {
  appPiClient: ["app-pi/client-messages.jsonl"],
  appPiServer: ["app-pi/server-messages.jsonl"],
  relayControl: ["relay/relay-control.jsonl"],
  crossPc: ["cross-pc/cross-pc.jsonl"],
  cockpitControl: ["cockpit/cockpit-control.jsonl"],
};

function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

function collectSchemaFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) return collectSchemaFiles(full);
    return entry.isFile() && entry.name.endsWith(".json") ? [full] : [];
  });
}

function fixtureLines(path: string): unknown[] {
  return readFileSync(path, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line) as unknown;
      } catch (error) {
        throw new Error(`${relative(protocolRoot, path)}:${index + 1}: invalid JSON: ${error}`);
      }
    });
}

function authDomainVectorErrors(manifest: Manifest): string[] {
  const relayControl = manifest.families.find((family) => family.id === "relayControl");
  if (!relayControl) return ["relayControl: missing from protocol manifest"];

  const schema = readJson<Record<string, unknown>>(join(protocolRoot, relayControl.schema));
  const schemaMetadata = schema["x-outpost-pi"];
  const authDomainPrefix =
    typeof schemaMetadata === "object" && schemaMetadata !== null && !Array.isArray(schemaMetadata)
      ? (schemaMetadata as Record<string, unknown>).authDomainPrefix
      : undefined;
  const vector = readJson<Record<string, unknown>>(join(fixturesRoot, "relay/auth-domain-vector.json"));
  const vectorPrefix = vector.authDomainPrefix;
  const nonceBase64 = vector.nonceBase64;
  const signingBytesBase64 = vector.signingBytesBase64;

  if (typeof authDomainPrefix !== "string" || authDomainPrefix.length === 0) {
    return ["relayControl: x-outpost-pi.authDomainPrefix must be a non-empty string"];
  }
  if (typeof vectorPrefix !== "string" || typeof nonceBase64 !== "string" || typeof signingBytesBase64 !== "string") {
    return ["relay/auth-domain-vector.json: expected authDomainPrefix, nonceBase64, and signingBytesBase64 strings"];
  }
  if (vectorPrefix !== authDomainPrefix) {
    return ["relay/auth-domain-vector.json: authDomainPrefix must match relayControl schema metadata"];
  }

  const expectedSigningBytes = Buffer.concat([Buffer.from(authDomainPrefix, "utf8"), Buffer.from(nonceBase64, "base64")]);
  if (expectedSigningBytes.toString("base64") !== signingBytesBase64) {
    return ["relay/auth-domain-vector.json: signingBytesBase64 must equal UTF-8 authDomainPrefix ++ decoded nonce"];
  }
  return [];
}

const ajv = new Ajv2020({
  strict: true,
  allErrors: true,
  allowUnionTypes: false,
  strictSchema: true,
});
addFormats(ajv);
ajv.addKeyword({ keyword: "x-outpost-pi", metaSchema: {} });

for (const schemaPath of collectSchemaFiles(schemaRoot)) {
  const schema = readJson<Record<string, unknown>>(schemaPath);
  if (typeof schema.$id === "string") {
    ajv.addSchema(schema);
  }
}

const manifest = readJson<Manifest>(join(schemaRoot, "manifest.json"));
const errors: string[] = authDomainVectorErrors(manifest);

for (const family of manifest.families) {
  const validate = ajv.getSchema(`https://kevoun.com/schemas/${family.schema.replace(/^schema\//, "")}`);
  if (!validate) {
    errors.push(`${family.id}: schema ${family.schema} did not compile`);
    continue;
  }

  const fixtureFiles = fixtureTargets[family.id] ?? [];
  if (fixtureFiles.length === 0) {
    errors.push(`${family.id}: no fixture target configured`);
    continue;
  }

  let validatedCount = 0;
  for (const fixtureRel of fixtureFiles) {
    const fixturePath = join(fixturesRoot, fixtureRel);
    const objects = fixtureLines(fixturePath);
    for (const [index, object] of objects.entries()) {
      validatedCount += 1;
      if (!validate(object)) {
        const detail = ajv.errorsText(validate.errors, { separator: "\n  " });
        errors.push(`${fixtureRel}:${index + 1}: ${family.id} fixture failed\n  ${detail}`);
      }
    }
  }

  if (validatedCount === 0) {
    errors.push(`${family.id}: fixture target had no JSONL objects`);
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Validated ${manifest.families.length} protocol schema fixture families.`);
}
