import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPayload,
  isLoopbackWebSocketUrl,
  isWorkBuddyTarget,
  parseArgs,
} from "../scripts/injector.mjs";

const contract = {
  target: { title: "WorkBuddy", urlSuffix: "/app.asar/renderer/index.html" },
};

test("parseArgs validates ports and actions", () => {
  const options = parseArgs(["--port", "9444", "--watch", "--json"]);
  assert.equal(options.port, 9444);
  assert.equal(options.action, "watch");
  assert.equal(options.json, true);
  assert.equal(parseArgs(["--validate"]).action, "validate");
  assert.throws(() => parseArgs(["--port", "80"]), /Invalid CDP port/);
  assert.throws(() => parseArgs(["--unknown"]), /Unknown argument/);
});

test("CDP websocket endpoints must remain loopback and same-port", () => {
  assert.equal(isLoopbackWebSocketUrl("ws://127.0.0.1:9432/devtools/page/abc", 9432), true);
  assert.equal(isLoopbackWebSocketUrl("ws://localhost:9432/devtools/page/abc", 9432), true);
  assert.equal(isLoopbackWebSocketUrl("ws://192.168.1.10:9432/devtools/page/abc", 9432), false);
  assert.equal(isLoopbackWebSocketUrl("ws://127.0.0.1:9433/devtools/page/abc", 9432), false);
});

test("only the official WorkBuddy main renderer shape is accepted", () => {
  const valid = {
    type: "page",
    title: "WorkBuddy",
    url: "file:///Applications/WorkBuddy.app/Contents/Resources/app.asar/renderer/index.html",
    webSocketDebuggerUrl: "ws://127.0.0.1:9432/devtools/page/abc",
  };
  assert.equal(isWorkBuddyTarget(valid, 9432, contract), true);
  assert.equal(isWorkBuddyTarget({ ...valid, title: "Login" }, 9432, contract), false);
  assert.equal(isWorkBuddyTarget({ ...valid, url: "https://example.com" }, 9432, contract), false);
  assert.equal(isWorkBuddyTarget({ ...valid, type: "webview" }, 9432, contract), false);
});

test("theme payload is complete, deterministic, and syntactically valid", async () => {
  const options = parseArgs([]);
  const first = await buildPayload(options);
  const second = await buildPayload(options);
  assert.equal(first.revision, second.revision);
  assert.equal(first.version, second.version);
  assert.equal(first.theme.id, "gothic-void-crusade");
  assert.equal(first.theme.appearance, "auto");
  assert.ok(first.source.length > 10_000);
  assert.match(first.source, /prefers-color-scheme: dark/);
  assert.match(first.source, /DEFAULT_PALETTES/);
  assert.match(first.source, /data-wbds-appearance/);
  assert.match(first.source, /--wbds-composer-opacity/);
  assert.match(first.source, /_mainArea_/);
  assert.doesNotMatch(first.source, /__WBDS_[A-Z_]+__/);
  assert.doesNotThrow(() => new Function(first.source));
});
