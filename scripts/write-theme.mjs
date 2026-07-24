#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

const [mode, ...args] = process.argv.slice(2);

function valueFor(name, fallback = "") {
  const index = args.indexOf(`--${name}`);
  if (index < 0) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`Missing value for --${name}`);
  return value;
}

function validateText(value, name, maxLength, fallback) {
  if (/\p{Cc}|\u2028|\u2029/u.test(value)) throw new Error(`${name} must be a single line`);
  return Array.from(value.trim()).slice(0, maxLength).join("") || fallback;
}

function validateChoice(value, name, choices) {
  if (!choices.includes(value)) throw new Error(`${name} must be one of: ${choices.join(", ")}`);
  return value;
}

async function atomicWrite(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, value, { mode: 0o600, flag: "wx" });
    await fs.rename(temporary, file);
    await fs.chmod(file, 0o600);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => {});
  }
}

if (mode !== "custom") {
  throw new Error("Usage: write-theme.mjs custom --output-dir DIR --image FILE [options]");
}

const outputDirArg = valueFor("output-dir");
if (!outputDirArg) throw new Error("--output-dir is required");
const outputDir = path.resolve(outputDirArg);
const requestedImage = valueFor("image", "background.jpg");
const image = path.basename(requestedImage);
if (image !== requestedImage || !/\.(?:png|jpe?g|webp)$/i.test(image)) {
  throw new Error("image must be a PNG, JPEG, or WebP filename inside the theme directory");
}
const imagePath = path.join(outputDir, image);
const imageStat = await fs.stat(imagePath);
if (!imageStat.isFile() || imageStat.size < 1 || imageStat.size > 16 * 1024 * 1024) {
  throw new Error("The prepared theme image must be between 1 byte and 16 MiB");
}

const name = validateText(valueFor("name", "我的 WorkBuddy Dream Skin"), "name", 80, "我的 WorkBuddy Dream Skin");
const appearance = validateChoice(valueFor("appearance", "auto"), "appearance", ["auto", "light", "dark"]);
const id = validateText(valueFor("id", `custom-${Date.now()}`), "id", 96, `custom-${Date.now()}`)
  .replace(/[^a-zA-Z0-9._-]+/g, "-");
const theme = {
  schema: "workbuddy-dream-skin-theme/1",
  id,
  name,
  appearance,
  image,
  art: {
    focusX: 0.72,
    focusY: 0.46,
    homeOpacity: 0.96,
    pageOpacity: 0.78,
    taskOpacity: 0.62,
    settingsOpacity: 0.28,
  },
  effects: {
    blur: 14,
    panelOpacity: 0.4,
    taskPanelOpacity: 0.44,
    lightPanelOpacity: 0.4,
    darkPanelOpacity: 0.54,
    lightPagePanelOpacity: 0.34,
    darkPagePanelOpacity: 0.46,
    lightTaskPanelOpacity: 0.44,
    darkTaskPanelOpacity: 0.52,
    lightSettingsPanelOpacity: 0.72,
    darkSettingsPanelOpacity: 0.78,
    lightComposerOpacity: 0.4,
    darkComposerOpacity: 0.52,
  },
};

await atomicWrite(path.join(outputDir, "theme.json"), `${JSON.stringify(theme, null, 2)}\n`);
console.log(JSON.stringify({ id: theme.id, name: theme.name, outputDir }));
