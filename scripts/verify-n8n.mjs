#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  MANAGED_NAMES,
  buildHostedChatWorkflow,
  hostedChatWebhookId,
  workflowFingerprint,
} from "./lib/n8n-workflows.mjs";

const MCP_PROTOCOL_VERSION = "2025-03-26";
const REQUEST_TIMEOUT_MS = 15_000;
const SECRET_ENV_KEYS = ["N8N_API_KEY", "N8N_MCP_TOKEN"];

export class VerifyError extends Error {
  constructor(message, { code = "VERIFY_FAILED", check } = {}) {
    super(message);
    this.name = "VerifyError";
    this.code = code;
    this.check = check;
  }
}

function requireValue(value, name) {
  if (!value) throw new VerifyError(`${name} is required`, { code: "CONFIG_ERROR", check: "configuration" });
  return value;
}

function httpUrl(value, name) {
  requireValue(value, name);
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new VerifyError(`${name} must be a valid HTTP(S) URL`, {
      code: "CONFIG_ERROR",
      check: "configuration",
    });
  }
  if (!/^https?:$/.test(url.protocol) || url.username || url.password || url.hash) {
    throw new VerifyError(`${name} must be an HTTP(S) URL without credentials or a fragment`, {
      code: "CONFIG_ERROR",
      check: "configuration",
    });
  }
  return url;
}

function redactText(value, secrets) {
  let text = String(value ?? "");
  for (const secret of secrets) {
    if (secret) text = text.split(secret).join("[REDACTED]");
  }
  return text;
}

function serviceBaseUrl(apiUrl) {
  const base = new URL(apiUrl);
  base.pathname = base.pathname.replace(/\/api\/v1\/?$/, "/");
  base.search = "";
  return base;
}

function endpoint(base, path) {
  const url = new URL(base);
  url.pathname = `${url.pathname.replace(/\/+$/, "")}/${path.replace(/^\/+/, "")}`;
  url.search = "";
  url.hash = "";
  return url;
}

async function fetchChecked(fetchImpl, url, init, check) {
  let response;
  try {
    response = await fetchImpl(url, {
      ...init,
      redirect: "manual",
      signal: init?.signal || AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch {
    throw new VerifyError(`${check} request failed`, { code: "HTTP_ERROR", check });
  }
  return response;
}

async function requireOk(fetchImpl, url, init, check) {
  const response = await fetchChecked(fetchImpl, url, init, check);
  if (!response.ok) {
    throw new VerifyError(`${check} returned HTTP ${response.status}`, {
      code: "HTTP_ERROR",
      check,
    });
  }
  return response;
}

async function readManagedState(stateFile) {
  requireValue(stateFile, "N8N_STATE_FILE");
  let state;
  try {
    state = JSON.parse(await readFile(resolve(stateFile), "utf8"));
  } catch {
    throw new VerifyError("N8N_STATE_FILE is unreadable or invalid", {
      code: "STATE_ERROR",
      check: "state",
    });
  }

  if (state?.version !== 1 || !state.workflows || typeof state.workflows !== "object") {
    throw new VerifyError("n8n state has an unsupported or incomplete format", {
      code: "STATE_ERROR",
      check: "state",
    });
  }

  const expected = {
    mcp: MANAGED_NAMES.mcpWorkflow,
    chat: MANAGED_NAMES.chatWorkflow,
  };
  const workflows = {};
  for (const [key, expectedName] of Object.entries(expected)) {
    const item = state.workflows[key];
    if (!item || typeof item.id !== "string" || !item.id || item.name !== expectedName) {
      throw new VerifyError(`managed ${key} workflow state is missing or invalid`, {
        code: "STATE_ERROR",
        check: "state",
      });
    }
    if (typeof item.fingerprint !== "string" || !/^[0-9a-f]{64}$/.test(item.fingerprint)) {
      throw new VerifyError(`managed ${key} workflow fingerprint is missing or invalid`, {
        code: "STATE_ERROR",
        check: "state",
      });
    }
    workflows[key] = { id: item.id, name: expectedName, fingerprint: item.fingerprint };
  }
  if (workflows.mcp.id === workflows.chat.id) {
    throw new VerifyError("managed workflow IDs must be distinct", {
      code: "STATE_ERROR",
      check: "state",
    });
  }
  return workflows;
}

function isPublished(workflow) {
  return workflow?.active === true || Boolean(workflow?.activeVersion?.versionId || workflow?.activeVersionId);
}

async function verifyManagedWorkflows({ fetchImpl, apiUrl, apiKey, workflows }) {
  if (!apiKey) return "skipped (N8N_API_KEY not set)";
  const origin = apiUrl.origin;
  for (const item of Object.values(workflows)) {
    const url = endpoint(apiUrl, `workflows/${encodeURIComponent(item.id)}`);
    if (url.origin !== origin) {
      throw new VerifyError("refusing to send N8N_API_KEY to another origin", {
        code: "ORIGIN_VIOLATION",
        check: "workflows",
      });
    }
    const response = await requireOk(
      fetchImpl,
      url,
      { headers: { Accept: "application/json", "X-N8N-API-KEY": apiKey } },
      "workflow API",
    );
    let workflow;
    try {
      workflow = await response.json();
    } catch {
      throw new VerifyError("workflow API returned invalid JSON", {
        code: "PROTOCOL_ERROR",
        check: "workflows",
      });
    }
    if (workflow?.id !== item.id || workflow?.name !== item.name) {
      throw new VerifyError("managed workflow identity does not match state", {
        code: "VERIFY_FAILED",
        check: "workflows",
      });
    }
    if (workflowFingerprint(workflow) !== item.fingerprint) {
      throw new VerifyError("managed workflow definition does not match its persisted fingerprint", {
        code: "VERIFY_FAILED",
        check: "workflows",
      });
    }
    if (!isPublished(workflow)) {
      throw new VerifyError(`managed ${item === workflows.mcp ? "mcp" : "chat"} workflow is not published`, {
        code: "VERIFY_FAILED",
        check: "workflows",
      });
    }
  }
  return "ok";
}

function parseSse(text) {
  const payloads = [];
  for (const block of text.replace(/\r\n/g, "\n").split(/\n\n+/)) {
    const data = block
      .split("\n")
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).replace(/^ /, ""))
      .join("\n");
    if (!data || data === "[DONE]") continue;
    try {
      payloads.push(JSON.parse(data));
    } catch {
      throw new VerifyError("MCP returned invalid SSE JSON", {
        code: "PROTOCOL_ERROR",
        check: "mcp",
      });
    }
  }
  return payloads;
}

async function parseMcpResponse(response, requestId, { allowEmpty = false } = {}) {
  const text = await response.text();
  if (!text.trim()) {
    if (allowEmpty) return null;
    throw new VerifyError("MCP returned an empty response", {
      code: "PROTOCOL_ERROR",
      check: "mcp",
    });
  }

  const contentType = response.headers.get("content-type")?.toLowerCase() || "";
  let messages;
  try {
    if (contentType.includes("text/event-stream")) messages = parseSse(text);
    else if (contentType.includes("application/json")) messages = [JSON.parse(text)];
    else {
      throw new VerifyError("MCP returned an unsupported content type", {
        code: "PROTOCOL_ERROR",
        check: "mcp",
      });
    }
  } catch (error) {
    if (error instanceof VerifyError) throw error;
    throw new VerifyError("MCP returned invalid JSON", {
      code: "PROTOCOL_ERROR",
      check: "mcp",
    });
  }

  const message = messages.find((item) => item?.id === requestId);
  if (!message || message.jsonrpc !== "2.0") {
    throw new VerifyError("MCP response did not contain the matching JSON-RPC result", {
      code: "PROTOCOL_ERROR",
      check: "mcp",
    });
  }
  if (message.error) {
    throw new VerifyError("MCP returned a JSON-RPC error", {
      code: "MCP_ERROR",
      check: "mcp",
    });
  }
  if (!Object.hasOwn(message, "result")) {
    throw new VerifyError("MCP response is missing a result", {
      code: "PROTOCOL_ERROR",
      check: "mcp",
    });
  }
  return message.result;
}

function calculatorSucceeded(result) {
  if (!result || result.isError === true) return false;
  const text = Array.isArray(result.content)
    ? result.content.map((item) => (typeof item?.text === "string" ? item.text : "")).join(" ")
    : "";
  if (!text) return false;
  return /(^|\D)5(?:\.0+)?(\D|$)/.test(text);
}

export async function verifyMcp({ fetchImpl = globalThis.fetch, mcpUrl, mcpToken }) {
  const url = httpUrl(mcpUrl, "N8N_MCP_URL");
  requireValue(mcpToken, "N8N_MCP_TOKEN");
  const accept = "application/json, text/event-stream";
  const commonHeaders = { Accept: accept, "Content-Type": "application/json" };
  const initialize = {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: MCP_PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: { name: "hermes-n8n-verifier", version: "1" },
    },
  };

  const unauthenticated = await fetchChecked(
    fetchImpl,
    url,
    { method: "POST", headers: commonHeaders, body: JSON.stringify(initialize) },
    "MCP unauthenticated probe",
  );
  await unauthenticated.body?.cancel().catch(() => {});
  if (![401, 403].includes(unauthenticated.status)) {
    throw new VerifyError("MCP accepted a request without authentication", {
      code: "AUTH_ERROR",
      check: "mcp-auth",
    });
  }

  let sessionId;
  const authenticatedHeaders = () => ({
    ...commonHeaders,
    Authorization: `Bearer ${mcpToken}`,
    ...(sessionId ? { "Mcp-Session-Id": sessionId } : {}),
  });

  async function post(body, requestId, { allowEmpty = false } = {}) {
    const response = await requireOk(
      fetchImpl,
      url,
      { method: "POST", headers: authenticatedHeaders(), body: JSON.stringify(body) },
      "MCP",
    );
    const suppliedSessionId = response.headers.get("mcp-session-id");
    if (suppliedSessionId) sessionId = suppliedSessionId;
    return parseMcpResponse(response, requestId, { allowEmpty });
  }

  let verificationSucceeded = false;
  try {
    const initialized = await post(initialize, initialize.id);
    if (typeof initialized?.protocolVersion !== "string") {
      throw new VerifyError("MCP initialize result is invalid", {
        code: "PROTOCOL_ERROR",
        check: "mcp",
      });
    }

    await post(
      { jsonrpc: "2.0", method: "notifications/initialized", params: {} },
      undefined,
      { allowEmpty: true },
    );

    const tools = await post({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, 2);
    if (!Array.isArray(tools?.tools)) {
      throw new VerifyError("MCP tools/list result is invalid", {
        code: "PROTOCOL_ERROR",
        check: "mcp",
      });
    }
    if (!tools.tools.some((tool) => tool?.name === "Calculator")) {
      throw new VerifyError("MCP Calculator tool is missing", {
        code: "VERIFY_FAILED",
        check: "mcp",
      });
    }

    const calculation = await post(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: { name: "Calculator", arguments: { input: "2+3" } },
      },
      3,
    );
    if (!calculatorSucceeded(calculation)) {
      throw new VerifyError("MCP Calculator did not successfully evaluate the readiness input", {
        code: "VERIFY_FAILED",
        check: "mcp",
      });
    }
    verificationSucceeded = true;
    return { status: "ok", session: sessionId ? "established" : "not supplied" };
  } finally {
    if (sessionId) {
      let closeResponse;
      try {
        closeResponse = await fetchChecked(
          fetchImpl,
          url,
          { method: "DELETE", headers: authenticatedHeaders() },
          "MCP session close",
        );
        await closeResponse.body?.cancel().catch(() => {});
      } catch (error) {
        if (verificationSucceeded) throw error;
      }
      if (verificationSucceeded && closeResponse && !closeResponse.ok) {
        throw new VerifyError(`MCP session close returned HTTP ${closeResponse.status}`, {
          code: "HTTP_ERROR",
          check: "mcp",
        });
      }
    }
  }
}

export async function verifyN8n({
  apiUrl,
  apiKey,
  mcpUrl,
  mcpToken,
  stateFile,
  smartRouterUrl = "http://smart-router:8080",
  fetchImpl = globalThis.fetch,
} = {}) {
  const secrets = [apiKey, mcpToken].filter(Boolean);
  try {
    if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl must be a function");
    const parsedApiUrl = httpUrl(apiUrl, "N8N_API_URL");
    const parsedRouterUrl = httpUrl(smartRouterUrl, "SMART_ROUTER_URL");
    const workflows = await readManagedState(stateFile);
    const base = serviceBaseUrl(parsedApiUrl);
    const webhookId = hostedChatWebhookId(buildHostedChatWorkflow({ id: "verification", name: "verification" }));
    if (!webhookId) {
      throw new VerifyError("managed hosted chat webhook ID is missing", {
        code: "VERIFY_FAILED",
        check: "hosted-chat",
      });
    }

    await requireOk(fetchImpl, endpoint(base, "healthz"), { headers: { Accept: "application/json" } }, "n8n healthz");
    await requireOk(
      fetchImpl,
      endpoint(parsedRouterUrl, "ready"),
      { headers: { Accept: "application/json" } },
      "Smart Router ready",
    );
    // GET on the chat webhook serves only the static chat shell, which n8n
    // returns to anonymous callers by design. Authentication is enforced on the
    // POST that actually submits a message, so probe that instead.
    const hostedChat = await fetchChecked(
      fetchImpl,
      endpoint(base, `webhook/${encodeURIComponent(webhookId)}/chat`),
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ action: "sendMessage", chatInput: "verification", sessionId: "verification" }),
      },
      "hosted chat authentication",
    );
    await hostedChat.body?.cancel().catch(() => {});
    if (![401, 403].includes(hostedChat.status) && !(hostedChat.status >= 300 && hostedChat.status < 400)) {
      throw new VerifyError("hosted chat did not require n8n user authentication", {
        code: "AUTH_ERROR",
        check: "hosted-chat",
      });
    }

    const workflowStatus = await verifyManagedWorkflows({
      fetchImpl,
      apiUrl: parsedApiUrl,
      apiKey,
      workflows,
    });
    const mcp = await verifyMcp({ fetchImpl, mcpUrl, mcpToken });

    return {
      status: "ok",
      checks: {
        state: "ok",
        healthz: "ok",
        smartRouter: "ok",
        hostedChat: "ok",
        workflows: workflowStatus,
        mcp: mcp.status,
        mcpSession: mcp.session,
      },
    };
  } catch (error) {
    const message = redactText(error?.message || "verification failed", secrets);
    throw new VerifyError(message, {
      code: error?.code || "VERIFY_FAILED",
      check: error?.check || "verification",
    });
  }
}

export function configFromEnv(env = process.env) {
  return {
    apiUrl: env.N8N_API_URL,
    apiKey: env.N8N_API_KEY,
    mcpUrl: env.N8N_MCP_URL,
    mcpToken: env.N8N_MCP_TOKEN,
    stateFile: env.N8N_STATE_FILE,
    smartRouterUrl: env.SMART_ROUTER_URL || "http://smart-router:8080",
  };
}

async function main() {
  try {
    const result = await verifyN8n(configFromEnv());
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    const secrets = SECRET_ENV_KEYS.map((key) => process.env[key]).filter(Boolean);
    const output = {
      status: "error",
      code: error.code || "VERIFY_FAILED",
      check: error.check || "verification",
      message: redactText(error.message, secrets),
    };
    process.stderr.write(`${JSON.stringify(output)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main();
