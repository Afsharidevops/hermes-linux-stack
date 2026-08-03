import crypto from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire("/app/package.json");
const Database = require("better-sqlite3");
const database = new Database("/app/data/db/data.sqlite");
database.pragma("busy_timeout = 30000");

const keyName = "Open WebUI (hermes-linux-stack)";
const comboName = "OpenCode-Free";

let keyRow = database
  .prepare("SELECT key FROM apiKeys WHERE name = ? AND isActive = 1 ORDER BY createdAt ASC LIMIT 1")
  .get(keyName);
let keyStatus = "reused";
if (!keyRow?.key) {
  const now = new Date().toISOString();
  // 9router accepts its legacy sk-{random} key format and validates the exact
  // value against this local database. No management/provider credential is used.
  const apiKey = `sk-${crypto.randomBytes(24).toString("hex")}`;
  database
    .prepare("INSERT INTO apiKeys(id, key, name, machineId, isActive, createdAt) VALUES(?, ?, ?, ?, 1, ?)")
    .run(crypto.randomUUID(), apiKey, keyName, null, now);
  keyRow = { key: apiKey };
  keyStatus = "created";
}

let comboStatus = "unavailable";
let freeModelCount = 0;
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

  const now = new Date().toISOString();
  const existing = database.prepare("SELECT id FROM combos WHERE name = ? LIMIT 1").get(comboName);
  if (existing) {
    database
      .prepare("UPDATE combos SET kind = ?, models = ?, updatedAt = ? WHERE id = ?")
      .run("llm", JSON.stringify(freeModels), now, existing.id);
    comboStatus = "updated";
  } else {
    database
      .prepare("INSERT INTO combos(id, name, kind, models, createdAt, updatedAt) VALUES(?, ?, ?, ?, ?, ?)")
      .run(crypto.randomUUID(), comboName, "llm", JSON.stringify(freeModels), now, now);
    comboStatus = "created";
  }
} catch (error) {
  process.stderr.write(`OpenCode-Free combo warning: ${error.message}\n`);
} finally {
  database.close();
}

process.stdout.write(`OPENWEBUI_API_KEY=${keyRow.key}\n`);
process.stdout.write(`OPENWEBUI_KEY_STATUS=${keyStatus}\n`);
process.stdout.write(`OPENCODE_COMBO_STATUS=${comboStatus}\n`);
process.stdout.write(`OPENCODE_FREE_MODEL_COUNT=${freeModelCount}\n`);
