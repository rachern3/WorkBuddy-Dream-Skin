import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(here);

test("custom themes default to following the native/system appearance", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "wbds-theme-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  await fs.writeFile(path.join(directory, "background.jpg"), Buffer.from([0xff, 0xd8, 0xff, 0xd9]));

  await execFileAsync(process.execPath, [
    path.join(root, "scripts", "write-theme.mjs"),
    "custom",
    "--output-dir", directory,
    "--image", "background.jpg",
    "--id", "custom-test",
    "--name", "测试主题",
  ]);

  const theme = JSON.parse(await fs.readFile(path.join(directory, "theme.json"), "utf8"));
  assert.equal(theme.schema, "workbuddy-dream-skin-theme/1");
  assert.equal(theme.id, "custom-test");
  assert.equal(theme.name, "测试主题");
  assert.equal(theme.appearance, "auto");
  assert.equal(theme.image, "background.jpg");
  assert.equal(theme.art.taskOpacity, 0.48);
  assert.equal(theme.effects.taskPanelOpacity, 0.64);
  assert.equal(theme.effects.lightPanelOpacity, 0.48);
});

test("custom theme writer rejects unsupported appearance values", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "wbds-theme-invalid-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  await fs.writeFile(path.join(directory, "background.jpg"), Buffer.from([0xff, 0xd8, 0xff, 0xd9]));

  await assert.rejects(execFileAsync(process.execPath, [
    path.join(root, "scripts", "write-theme.mjs"),
    "custom",
    "--output-dir", directory,
    "--image", "background.jpg",
    "--appearance", "system-ish",
  ]), /appearance must be one of/);
});
