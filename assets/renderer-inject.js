((cssText, artUrl, themeConfig, selectorContract, version) => {
  const STATE_KEY = "__WORKBUDDY_DREAM_SKIN_STATE__";
  const STYLE_ID = "workbuddy-dream-skin-style";
  const ART_ID = "workbuddy-dream-skin-art";
  const ROOT_ATTRS = ["data-workbuddy-dream-skin", "data-wbds-route", "data-wbds-appearance"];
  const ROOT_VARS = [
    "--wbds-bg-rgb", "--wbds-panel-rgb", "--wbds-panel-alt-rgb",
    "--wbds-accent-rgb", "--wbds-text-rgb", "--wbds-muted-rgb", "--wbds-line",
    "--wbds-panel-opacity", "--wbds-page-panel-opacity", "--wbds-task-panel-opacity", "--wbds-settings-panel-opacity", "--wbds-composer-opacity",
    "--wbds-left-scrim-start", "--wbds-left-scrim-mid", "--wbds-left-scrim-end", "--wbds-blur",
    "--wbds-focus-x", "--wbds-focus-y", "--wbds-art-home-opacity", "--wbds-art-page-opacity",
    "--wbds-art-task-opacity", "--wbds-art-settings-opacity", "--wbds-art",
  ];

  const previous = window[STATE_KEY];
  if (typeof previous?.cleanup === "function") previous.cleanup();

  let observer = null;
  let scheduled = false;
  let stopped = false;
  const listeners = [];
  const metrics = { ensureCalls: 0, routeChanges: 0, repairs: 0 };

  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const numeric = (value, fallback) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  };
  const parseHex = (value, fallback) => {
    const match = /^#([0-9a-f]{6})$/i.exec(String(value || ""));
    const source = match ? match[1] : fallback.replace(/^#/, "");
    const number = Number.parseInt(source, 16);
    return `${number >> 16} ${(number >> 8) & 255} ${number & 255}`;
  };
  const colors = themeConfig?.colors || {};
  const art = themeConfig?.art || {};
  const effects = themeConfig?.effects || {};
  const DEFAULT_PALETTES = {
    light: {
      background: "#f4f7fb",
      panel: "#ffffff",
      panelAlt: "#eaf0f7",
      accent: "#2563eb",
      accentAlt: "#7c3aed",
      text: "#172033",
      muted: "#627086",
      line: "rgba(37, 99, 235, 0.20)",
    },
    dark: {
      background: "#080b12",
      panel: "#101620",
      panelAlt: "#182230",
      accent: "#9ad8ff",
      accentAlt: "#d7b7ff",
      text: "#eef7ff",
      muted: "#9eafbf",
      line: "rgba(154, 216, 255, 0.24)",
    },
  };

  const detectAppearance = () => {
    if (themeConfig?.appearance === "dark" || themeConfig?.appearance === "light") {
      return themeConfig.appearance;
    }
    const lightSelector = selectorContract?.themeSignals?.light;
    const darkSelector = selectorContract?.themeSignals?.dark;
    try {
      if (lightSelector && document.querySelector(lightSelector)) return "light";
      if (darkSelector && document.querySelector(darkSelector)) return "dark";
    } catch {}
    return window.matchMedia?.("(prefers-color-scheme: dark)")?.matches ? "dark" : "light";
  };

  const detectRoute = () => {
    const visible = (selector) => {
      try {
        return [...document.querySelectorAll(selector)].some((element) => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 320 && rect.height > 200 && style.display !== "none" && style.visibility !== "hidden";
        });
      } catch {
        return false;
      }
    };
    if (visible(".claw-workspace")) return "assistant";
    if (visible(".workbuddy-collab, .landing")) return "projects";
    if (visible(".expert-center-page")) return "experts";
    if (visible(".automation-main-page")) return "automation";
    if (visible(".my-files-panel, .tencent-docs-panel")) return "resources";
    if (visible("[class*='settings'], [data-view-id*='settings']")) return "settings";
    if (visible(".chat-container:not(.chat-container--welcome), .detail-layout, .detail-panel")) return "task";
    if (visible(".wb-home-page, .main-content--welcome, .chat-container--welcome")) return "home";
    return "shell";
  };

  const resolvePalette = (appearance) => {
    const fallback = DEFAULT_PALETTES[appearance] || DEFAULT_PALETTES.light;
    const modeColors = colors?.[appearance] && typeof colors[appearance] === "object"
      ? colors[appearance] : {};
    const legacy = colors && typeof colors === "object" ? colors : {};
    const explicitAppearance = themeConfig?.appearance === "light" || themeConfig?.appearance === "dark";
    const structural = new Set(["background", "panel", "panelAlt", "text", "muted"]);
    const palette = { ...fallback };
    for (const name of Object.keys(fallback)) {
      if (typeof modeColors[name] === "string") palette[name] = modeColors[name];
      else if (typeof legacy[name] === "string" && (explicitAppearance || appearance === "dark" || !structural.has(name))) {
        palette[name] = legacy[name];
      }
    }
    return palette;
  };

  const applyVariables = (root, appearance) => {
    const palette = resolvePalette(appearance);
    const configuredPanelOpacity = clamp(numeric(effects.panelOpacity, 0.72), 0.25, 1);
    const configuredTaskOpacity = clamp(numeric(effects.taskPanelOpacity, 0.92), 0.35, 1);
    const modePrefix = appearance === "dark" ? "dark" : "light";
    const modeValue = (suffix, fallback) => numeric(effects[`${modePrefix}${suffix}`], fallback);
    const panelOpacity = clamp(Math.min(modeValue("PanelOpacity",
      Math.min(configuredPanelOpacity, appearance === "dark" ? 0.54 : 0.4)), appearance === "dark" ? 0.54 : 0.4), 0.25, 0.9);
    const pagePanelOpacity = clamp(modeValue("PagePanelOpacity", appearance === "dark" ? 0.46 : 0.34), 0.22, 0.82);
    const taskPanelOpacity = clamp(Math.min(modeValue("TaskPanelOpacity",
      Math.min(configuredTaskOpacity, appearance === "dark" ? 0.52 : 0.44)), appearance === "dark" ? 0.52 : 0.44), 0.32, 0.9);
    const settingsPanelOpacity = clamp(modeValue("SettingsPanelOpacity", appearance === "dark" ? 0.78 : 0.72), 0.5, 0.92);
    const composerOpacity = clamp(Math.min(modeValue("ComposerOpacity", appearance === "dark" ? 0.52 : 0.4), appearance === "dark" ? 0.52 : 0.4), 0.3, 0.9);
    const blur = clamp(Math.min(numeric(effects.blur, 14), appearance === "dark" ? 13 : 11), 0, 40);
    const scrimStart = clamp(modeValue("LeftScrimStart", appearance === "dark" ? 0.46 : 0.24), 0, 0.85);
    const scrimMid = clamp(modeValue("LeftScrimMid", appearance === "dark" ? 0.14 : 0.07), 0, 0.5);
    const scrimEnd = clamp(modeValue("LeftScrimEnd", appearance === "dark" ? 0.04 : 0.02), 0, 0.25);
    const values = {
      "--wbds-bg-rgb": parseHex(palette.background, DEFAULT_PALETTES[appearance].background),
      "--wbds-panel-rgb": parseHex(palette.panel, DEFAULT_PALETTES[appearance].panel),
      "--wbds-panel-alt-rgb": parseHex(palette.panelAlt, DEFAULT_PALETTES[appearance].panelAlt),
      "--wbds-accent-rgb": parseHex(palette.accent, DEFAULT_PALETTES[appearance].accent),
      "--wbds-text-rgb": parseHex(palette.text, DEFAULT_PALETTES[appearance].text),
      "--wbds-muted-rgb": parseHex(palette.muted, DEFAULT_PALETTES[appearance].muted),
      "--wbds-line": String(palette.line),
      "--wbds-panel-opacity": String(panelOpacity),
      "--wbds-page-panel-opacity": String(pagePanelOpacity),
      "--wbds-task-panel-opacity": String(taskPanelOpacity),
      "--wbds-settings-panel-opacity": String(settingsPanelOpacity),
      "--wbds-composer-opacity": String(composerOpacity),
      "--wbds-left-scrim-start": String(scrimStart),
      "--wbds-left-scrim-mid": String(scrimMid),
      "--wbds-left-scrim-end": String(scrimEnd),
      "--wbds-blur": `${blur}px`,
      "--wbds-focus-x": `${clamp(numeric(art.focusX, 0.72), 0, 1) * 100}%`,
      "--wbds-focus-y": `${clamp(numeric(art.focusY, 0.46), 0, 1) * 100}%`,
      "--wbds-art-home-opacity": String(clamp(numeric(art.homeOpacity, 0.96), 0, 1)),
      "--wbds-art-page-opacity": String(clamp(numeric(art.pageOpacity, 0.78), 0.58, 0.9)),
      "--wbds-art-task-opacity": String(clamp(numeric(art.taskOpacity, 0.62), 0.58, 0.82)),
      "--wbds-art-settings-opacity": String(clamp(numeric(art.settingsOpacity, 0.28), 0.28, 0.6)),
      "--wbds-art": artUrl ? `url(${JSON.stringify(artUrl)})` : "none",
    };
    for (const [name, value] of Object.entries(values)) root.style.setProperty(name, value);
  };

  const ensure = () => {
    if (stopped || !document.documentElement) return;
    metrics.ensureCalls += 1;
    const root = document.documentElement;
    const head = document.head || root.querySelector("head");
    const body = document.body;
    if (!head || !body) return;

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      style.textContent = cssText;
      head.append(style);
      metrics.repairs += 1;
    } else if (style.textContent !== cssText) {
      style.textContent = cssText;
      metrics.repairs += 1;
    }

    let artLayer = document.getElementById(ART_ID);
    if (!artLayer) {
      artLayer = document.createElement("div");
      artLayer.id = ART_ID;
      artLayer.setAttribute("aria-hidden", "true");
      body.prepend(artLayer);
      metrics.repairs += 1;
    }

    const appearance = detectAppearance();
    applyVariables(root, appearance);
    root.setAttribute("data-workbuddy-dream-skin", "active");
    root.setAttribute("data-wbds-appearance", appearance);
    const nextRoute = detectRoute();
    if (root.getAttribute("data-wbds-route") !== nextRoute) metrics.routeChanges += 1;
    root.setAttribute("data-wbds-route", nextRoute);
  };

  const schedule = () => {
    if (scheduled || stopped) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      ensure();
    });
  };

  const listen = (target, name, handler) => {
    target?.addEventListener?.(name, handler);
    listeners.push(() => target?.removeEventListener?.(name, handler));
  };

  const start = () => {
    ensure();
    observer = new MutationObserver(schedule);
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "data-theme", "data-vscode-theme-name"] });
    listen(window, "hashchange", schedule);
    listen(window, "popstate", schedule);
    listen(window.matchMedia?.("(prefers-color-scheme: dark)"), "change", schedule);
    if (typeof globalThis.navigation?.addEventListener === "function") listen(globalThis.navigation, "navigate", schedule);
  };

  const cleanup = () => {
    stopped = true;
    observer?.disconnect();
    for (const remove of listeners.splice(0)) remove();
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(ART_ID)?.remove();
    const root = document.documentElement;
    for (const name of ROOT_ATTRS) root?.removeAttribute(name);
    for (const name of ROOT_VARS) root?.style?.removeProperty(name);
    if (window[STATE_KEY]?.cleanup === cleanup) delete window[STATE_KEY];
  };

  window[STATE_KEY] = {
    version,
    themeId: themeConfig?.id || null,
    selectorsSchema: selectorContract?.schema || null,
    installedAt: new Date().toISOString(),
    metrics,
    ensure,
    cleanup,
    health: () => ({
      active: document.documentElement?.getAttribute("data-workbuddy-dream-skin") === "active",
      themeId: themeConfig?.id || null,
      version,
      route: document.documentElement?.getAttribute("data-wbds-route") || null,
      appearance: document.documentElement?.getAttribute("data-wbds-appearance") || null,
      style: Boolean(document.getElementById(STYLE_ID)),
      art: Boolean(document.getElementById(ART_ID)),
      markers: Object.fromEntries((selectorContract?.selectors || []).map((entry) => {
        try { return [entry.key, document.querySelectorAll(entry.selector).length]; }
        catch { return [entry.key, -1]; }
      })),
      metrics: { ...metrics },
    }),
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})(
  __WBDS_CSS_JSON__,
  __WBDS_ART_URL_JSON__,
  __WBDS_THEME_JSON__,
  __WBDS_SELECTORS_JSON__,
  __WBDS_VERSION_JSON__
);
