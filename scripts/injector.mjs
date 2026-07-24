#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.dirname(SCRIPT_DIR);
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);
const MAX_ART_BYTES = 16 * 1024 * 1024;
const DEFAULT_WAIT_MS = 30_000;

export function parseArgs(argv) {
  const options = {
    port: 9432,
    waitMs: DEFAULT_WAIT_MS,
    themeDir: path.join(ROOT, "presets", "gothic-void-crusade"),
    cssPath: path.join(ROOT, "assets", "workbuddy-dream-skin.css"),
    runtimePath: path.join(ROOT, "assets", "renderer-inject.js"),
    selectorsPath: path.join(ROOT, "assets", "selectors.json"),
    versionPath: path.join(ROOT, "VERSION"),
    statePath: null,
    action: "once",
    json: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = () => {
      const next = argv[++index];
      if (!next) throw new Error(`${arg} requires a value`);
      return next;
    };
    if (arg === "--port") options.port = Number(value());
    else if (arg === "--wait") options.waitMs = Number(value()) * 1000;
    else if (arg === "--theme") options.themeDir = path.resolve(value());
    else if (arg === "--css") options.cssPath = path.resolve(value());
    else if (arg === "--runtime") options.runtimePath = path.resolve(value());
    else if (arg === "--selectors") options.selectorsPath = path.resolve(value());
    else if (arg === "--state") options.statePath = path.resolve(value());
    else if (arg === "--watch") options.action = "watch";
    else if (arg === "--once") options.action = "once";
    else if (arg === "--cleanup") options.action = "cleanup";
    else if (arg === "--status") options.action = "status";
    else if (arg === "--probe") options.action = "probe";
    else if (arg === "--validate") options.action = "validate";
    else if (arg === "--json") options.json = true;
    else if (arg === "--help" || arg === "-h") options.action = "help";
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`Invalid CDP port: ${options.port}`);
  }
  return options;
}

export function isLoopbackWebSocketUrl(rawUrl, expectedPort) {
  try {
    const url = new URL(rawUrl);
    return (url.protocol === "ws:" || url.protocol === "wss:") &&
      LOOPBACK_HOSTS.has(url.hostname) && Number(url.port) === Number(expectedPort);
  } catch {
    return false;
  }
}

export function isWorkBuddyTarget(target, port, contract) {
  if (target?.type !== "page" || !target.webSocketDebuggerUrl ||
      !isLoopbackWebSocketUrl(target.webSocketDebuggerUrl, port)) return false;
  if (target.title !== contract.target.title) return false;
  try {
    const url = new URL(target.url);
    return url.protocol === "file:" && url.pathname.endsWith(contract.target.urlSuffix);
  } catch {
    return false;
  }
}

function replaceToken(source, token, value) {
  const first = source.indexOf(token);
  if (first < 0 || source.indexOf(token, first + token.length) >= 0) {
    throw new Error(`Runtime token must occur exactly once: ${token}`);
  }
  return source.slice(0, first) + value + source.slice(first + token.length);
}

async function findBackground(themeDir) {
  for (const name of ["background.jpg", "background.jpeg", "background.png", "background.webp", "background.gif"]) {
    const candidate = path.join(themeDir, name);
    try {
      const stat = await fs.stat(candidate);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_ART_BYTES) {
        throw new Error(`Background must be between 1 byte and 16 MiB: ${candidate}`);
      }
      return candidate;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  throw new Error(`No supported background image in ${themeDir}`);
}

export async function buildPayload(options) {
  const [cssText, runtimeTemplate, selectorsText, themeText, versionText] = await Promise.all([
    fs.readFile(options.cssPath, "utf8"),
    fs.readFile(options.runtimePath, "utf8"),
    fs.readFile(options.selectorsPath, "utf8"),
    fs.readFile(path.join(options.themeDir, "theme.json"), "utf8"),
    fs.readFile(options.versionPath, "utf8"),
  ]);
  const selectors = JSON.parse(selectorsText);
  const theme = JSON.parse(themeText);
  if (selectors.schema !== "workbuddy-dream-skin-selectors/1") {
    throw new Error(`Unsupported selectors schema: ${selectors.schema}`);
  }
  if (theme.schema !== "workbuddy-dream-skin-theme/1") {
    throw new Error(`Unsupported theme schema: ${theme.schema}`);
  }
  const backgroundPath = await findBackground(options.themeDir);
  const background = await fs.readFile(backgroundPath);
  const revision = crypto.createHash("sha256")
    .update(cssText).update(runtimeTemplate).update(themeText).update(background)
    .digest("hex").slice(0, 16);
  // User themes are staged at the stable current-theme/background.* path.
  // Chromium otherwise keeps showing the previous file from its image cache
  // after a hot theme switch, even though the bytes on disk have changed.
  const artFileUrl = pathToFileURL(backgroundPath);
  artFileUrl.searchParams.set("wbds", revision);
  const artUrl = artFileUrl.href;
  const version = `${versionText.trim()}+${revision}`;
  let source = runtimeTemplate;
  source = replaceToken(source, "__WBDS_CSS_JSON__", JSON.stringify(cssText));
  source = replaceToken(source, "__WBDS_ART_URL_JSON__", JSON.stringify(artUrl));
  source = replaceToken(source, "__WBDS_THEME_JSON__", JSON.stringify(theme));
  source = replaceToken(source, "__WBDS_SELECTORS_JSON__", JSON.stringify(selectors));
  source = replaceToken(source, "__WBDS_VERSION_JSON__", JSON.stringify(version));
  return { source, selectors, theme, version, revision, backgroundPath, artUrl };
}

async function fetchJson(url, timeoutMs = 2_500) {
  const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs), cache: "no-store" });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  return response.json();
}

export async function getBrowserIdentity(port) {
  const value = await fetchJson(`http://127.0.0.1:${port}/json/version`);
  if (!String(value.Browser || "").includes("Chrome/") ||
      !String(value["User-Agent"] || "").includes("WorkBuddy/") ||
      !isLoopbackWebSocketUrl(value.webSocketDebuggerUrl, port)) {
    throw new Error(`Port ${port} is not a verified WorkBuddy CDP endpoint`);
  }
  return {
    browser: value.Browser,
    userAgent: value["User-Agent"],
    webSocketDebuggerUrl: value.webSocketDebuggerUrl,
    browserId: new URL(value.webSocketDebuggerUrl).pathname.split("/").pop(),
  };
}

export async function listTargets(port, contract) {
  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  if (!Array.isArray(targets)) throw new Error("CDP target list is not an array");
  return targets.filter((target) => isWorkBuddyTarget(target, port, contract));
}

class CdpSession {
  constructor(url, timeoutMs = 10_000) {
    this.url = url;
    this.timeoutMs = timeoutMs;
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;
    this.closeListeners = new Set();
  }

  async open() {
    this.socket = new WebSocket(this.url);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Timed out opening ${this.url}`)), this.timeoutMs);
      this.socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
      this.socket.addEventListener("error", () => { clearTimeout(timer); reject(new Error(`WebSocket error: ${this.url}`)); }, { once: true });
    });
    this.socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data));
      if (!message.id) return;
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
    });
    this.socket.addEventListener("close", () => {
      this.closed = true;
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error("CDP WebSocket closed"));
      }
      this.pending.clear();
      for (const listener of this.closeListeners) listener();
    });
    return this;
  }

  onClose(listener) { this.closeListeners.add(listener); }

  send(method, params = {}) {
    if (this.closed || this.socket?.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error("CDP session is not open"));
    }
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP ${method} timed out`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
    });
    this.socket.send(JSON.stringify({ id, method, params }));
    return promise;
  }

  close() {
    if (!this.closed) this.socket?.close();
    this.closed = true;
  }
}

async function evaluate(session, expression) {
  const result = await session.send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
    userGesture: false,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text || "Renderer evaluation failed");
  }
  return result.result?.value;
}

async function verifyRenderer(session, contract) {
  const contractJson = JSON.stringify(contract);
  return evaluate(session, `(() => {
    const contract = ${contractJson};
    const markers = Object.fromEntries(contract.selectors.map((entry) => {
      try { return [entry.key, document.querySelectorAll(entry.selector).length]; }
      catch { return [entry.key, -1]; }
    }));
    return {
      title: document.title,
      protocol: location.protocol,
      pathOk: location.pathname.endsWith(contract.target.urlSuffix),
      readyState: document.readyState,
      markers,
      verified: document.title === contract.target.title && location.protocol === 'file:' &&
        location.pathname.endsWith(contract.target.urlSuffix) && markers.root === 1 &&
        (markers.shell > 0 || markers.home > 0 || document.body?.classList.contains('agent-ui-theme')),
    };
  })()`);
}

async function connectVerifiedTarget(target, contract) {
  const session = await new CdpSession(target.webSocketDebuggerUrl).open();
  try {
    const verification = await verifyRenderer(session, contract);
    if (!verification?.verified) throw new Error(`Target ${target.id} failed WorkBuddy DOM verification`);
    return { session, verification };
  } catch (error) {
    session.close();
    throw error;
  }
}

async function installIntoTarget(session, payload) {
  await session.send("Page.enable");
  await session.send("Runtime.enable");
  await session.send("Page.addScriptToEvaluateOnNewDocument", { source: payload.source });
  await evaluate(session, payload.source);
  return evaluate(session, `window.__WORKBUDDY_DREAM_SKIN_STATE__?.health?.() ?? null`);
}

async function waitForTargets(port, contract, waitMs) {
  const deadline = Date.now() + waitMs;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      await getBrowserIdentity(port);
      const targets = await listTargets(port, contract);
      if (targets.length) return targets;
      lastError = new Error("No WorkBuddy main renderer target yet");
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`No verified WorkBuddy renderer on 127.0.0.1:${port}: ${lastError?.message || "timed out"}`);
}

async function writeState(statePath, value) {
  if (!statePath) return;
  await fs.mkdir(path.dirname(statePath), { recursive: true, mode: 0o700 });
  const temporary = `${statePath}.tmp-${process.pid}`;
  await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await fs.rename(temporary, statePath);
}

async function removeState(statePath) {
  if (!statePath) return;
  await fs.rm(statePath, { force: true });
}

async function assertNoLiveInjector(statePath) {
  if (!statePath) return;
  try {
    const state = JSON.parse(await fs.readFile(statePath, "utf8"));
    if (state.pid && state.pid !== process.pid) {
      try {
        process.kill(state.pid, 0);
        throw new Error(`Another injector is already running (PID ${state.pid})`);
      } catch (error) {
        if (error?.code !== "ESRCH") throw error;
      }
    }
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

function help() {
  return `WorkBuddy Dream Skin injector

Usage:
  injector.mjs --port 9432 --watch [--theme DIR] [--state FILE]
  injector.mjs --port 9432 --once [--theme DIR]
  injector.mjs --port 9432 --status --json
  injector.mjs --port 9432 --cleanup
  injector.mjs --port 9432 --probe --json
  injector.mjs --validate [--theme DIR]`;
}

async function run(options) {
  const selectors = JSON.parse(await fs.readFile(options.selectorsPath, "utf8"));
  if (options.action === "help") {
    console.log(help());
    return;
  }
  if (options.action === "validate") {
    const payload = await buildPayload(options);
    console.log(JSON.stringify({ ok: true, themeId: payload.theme.id, version: payload.version }));
    return;
  }
  const browser = await getBrowserIdentity(options.port);
  const targets = await waitForTargets(options.port, selectors, options.waitMs);

  if (options.action === "probe") {
    const { session, verification } = await connectVerifiedTarget(targets[0], selectors);
    session.close();
    const result = { ok: true, port: options.port, browser, target: { id: targets[0].id, title: targets[0].title }, verification };
    console.log(options.json ? JSON.stringify(result) : `Verified WorkBuddy renderer on 127.0.0.1:${options.port}`);
    return;
  }

  if (options.action === "cleanup" || options.action === "status") {
    const results = [];
    for (const target of targets) {
      const { session, verification } = await connectVerifiedTarget(target, selectors);
      const value = options.action === "cleanup"
        ? await evaluate(session, `(() => { const state = window.__WORKBUDDY_DREAM_SKIN_STATE__; if (typeof state?.cleanup === 'function') state.cleanup(); return { cleaned: true, active: Boolean(window.__WORKBUDDY_DREAM_SKIN_STATE__) }; })()`)
        : await evaluate(session, `window.__WORKBUDDY_DREAM_SKIN_STATE__?.health?.() ?? { active: false }`);
      results.push({ target: target.id, verification, ...value });
      session.close();
    }
    const result = { ok: true, port: options.port, browserId: browser.browserId, results };
    console.log(options.json ? JSON.stringify(result) : JSON.stringify(result, null, 2));
    return;
  }

  const payload = await buildPayload(options);
  if (options.action === "once") {
    const installed = [];
    for (const target of targets) {
      const { session } = await connectVerifiedTarget(target, selectors);
      installed.push({ target: target.id, health: await installIntoTarget(session, payload) });
      session.close();
    }
    console.log(JSON.stringify({ ok: true, version: payload.version, installed }, null, options.json ? 0 : 2));
    return;
  }

  await assertNoLiveInjector(options.statePath);
  const sessions = new Map();
  let stopping = false;
  const stop = () => { stopping = true; };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  process.on("SIGHUP", stop);

  await writeState(options.statePath, {
    schema: 1,
    pid: process.pid,
    port: options.port,
    browserId: browser.browserId,
    version: payload.version,
    themeId: payload.theme.id,
    themeDir: options.themeDir,
    startedAt: new Date().toISOString(),
  });

  try {
    let consecutivePollFailures = 0;
    while (!stopping) {
      let current = [];
      try {
        current = await listTargets(options.port, selectors);
        consecutivePollFailures = 0;
      }
      catch (error) {
        consecutivePollFailures += 1;
        if (!stopping && consecutivePollFailures === 1) {
          console.error(`[WorkBuddyDreamSkin] CDP poll failed: ${error.message}`);
        }
        if (consecutivePollFailures >= 5) stopping = true;
      }
      const currentIds = new Set(current.map((target) => target.id));
      for (const [id, session] of sessions) {
        if (!currentIds.has(id) || session.closed) {
          session.close();
          sessions.delete(id);
        }
      }
      for (const target of current) {
        if (sessions.has(target.id)) continue;
        try {
          const { session } = await connectVerifiedTarget(target, selectors);
          const health = await installIntoTarget(session, payload);
          session.onClose(() => sessions.delete(target.id));
          sessions.set(target.id, session);
          console.log(`[WorkBuddyDreamSkin] injected target=${target.id} route=${health?.route || "unknown"} version=${payload.version}`);
        } catch (error) {
          console.error(`[WorkBuddyDreamSkin] target ${target.id} rejected: ${error.message}`);
        }
      }
      if (!stopping) await new Promise((resolve) => setTimeout(resolve, 1_000));
    }
  } finally {
    for (const session of sessions.values()) session.close();
    await removeState(options.statePath);
  }
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isMain) {
  run(parseArgs(process.argv.slice(2))).catch((error) => {
    console.error(`[WorkBuddyDreamSkin] ${error.stack || error.message}`);
    process.exitCode = 1;
  });
}
