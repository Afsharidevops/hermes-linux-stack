import crypto from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire("/app/package.json");
const Database = require("better-sqlite3");
const database = new Database("/app/data/db/data.sqlite");
database.pragma("busy_timeout = 30000");

const provisionHermes = process.env.PROVISION_HERMES === "true";
const provisionOpenWebUI = process.env.PROVISION_OPENWEBUI === "true";
const hermesModelName = process.env.HERMES_MODEL_NAME || "ai";

function provisionKey(keyName) {
  let row = database
    .prepare("SELECT key FROM apiKeys WHERE name = ? AND isActive = 1 ORDER BY createdAt ASC LIMIT 1")
    .get(keyName);
  let status = "reused";
  if (!row?.key) {
    const now = new Date().toISOString();
    // 9router accepts its legacy sk-{random} key format and validates the exact
    // value against this local database. No management/provider credential is used.
    const apiKey = `sk-${crypto.randomBytes(24).toString("hex")}`;
    database
      .prepare("INSERT INTO apiKeys(id, key, name, machineId, isActive, createdAt) VALUES(?, ?, ?, ?, 1, ?)")
      .run(crypto.randomUUID(), apiKey, keyName, null, now);
    row = { key: apiKey };
    status = "created";
  }
  return { key: row.key, status };
}

function upsertCombo(name, models) {
  const now = new Date().toISOString();
  const existing = database.prepare("SELECT id FROM combos WHERE name = ? LIMIT 1").get(name);
  if (existing) {
    database
      .prepare("UPDATE combos SET kind = ?, models = ?, updatedAt = ? WHERE id = ?")
      .run("llm", JSON.stringify(models), now, existing.id);
    return "updated";
  }
  database
    .prepare("INSERT INTO combos(id, name, kind, models, createdAt, updatedAt) VALUES(?, ?, ?, ?, ?, ?)")
    .run(crypto.randomUUID(), name, "llm", JSON.stringify(models), now, now);
  return "created";
}

const openWebUIKey = provisionOpenWebUI
  ? provisionKey("Open WebUI (hermes-linux-stack)")
  : null;
const hermesKey = provisionHermes
  ? provisionKey("Hermes Agent (hermes-linux-stack)")
  : null;

let openCodeComboStatus = "not-requested";
let aiComboStatus = "not-requested";
let freeModelCount = 0;
if (provisionOpenWebUI || (provisionHermes && hermesModelName === "ai")) {
  try {
    const response = await fetch("https://opencode.ai/zen/v1/models", {
      headers: { "x-opencode-client": "desktop" },
      signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) throw new Error(`OpenCode model catalog returned ${response.status}`);
    const catalog = await response.json();
    const freeModels = (catalog.data || [])
      .map((model) => model?.id)
      .filter((id) => typeof id === "string" && (id.endsWith("-free") || id === "big-pickle"))
      .map((id) => `oc/${id}`);
    freeModelCount = freeModels.length;
    if (freeModelCount === 0) throw new Error("OpenCode returned no currently free models");

    if (provisionOpenWebUI) openCodeComboStatus = upsertCombo("OpenCode-Free", freeModels);
    if (provisionHermes && hermesModelName === "ai") aiComboStatus = upsertCombo("ai", freeModels);
  } catch (error) {
    if (provisionOpenWebUI) openCodeComboStatus = "unavailable";
    if (provisionHermes && hermesModelName === "ai") aiComboStatus = "unavailable";
    process.stderr.write(`OpenCode free-model combo warning: ${error.message}\n`);
  }
}

database.close();

if (openWebUIKey) {
  process.stdout.write(`OPENWEBUI_API_KEY=${openWebUIKey.key}\n`);
  process.stdout.write(`OPENWEBUI_KEY_STATUS=${openWebUIKey.status}\n`);
}
if (hermesKey) {
  process.stdout.write(`HERMES_API_KEY=${hermesKey.key}\n`);
  process.stdout.write(`HERMES_KEY_STATUS=${hermesKey.status}\n`);
}
process.stdout.write(`OPENCODE_COMBO_STATUS=${openCodeComboStatus}\n`);
process.stdout.write(`AI_COMBO_STATUS=${aiComboStatus}\n`);
process.stdout.write(`OPENCODE_FREE_MODEL_COUNT=${freeModelCount}\n`);
