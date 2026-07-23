((cssText, artUrl, themeConfig, selectorContract, version) => {
  const STATE_KEY = "__WORKBUDDY_DREAM_SKIN_STATE__";
  const STYLE_ID = "workbuddy-dream-skin-style";
  const ART_ID = "workbuddy-dream-skin-art";
  const ROOT_ATTRS = ["data-workbuddy-dream-skin", "data-wbds-route", "data-wbds-appearance"];
  const ROOT_VARS = [
    "--wbds-bg-rgb", "--wbds-panel-rgb", "--wbds-panel-alt-rgb",
    "--wbds-accent-rgb", "--wbds-text-rgb", "--wbds-muted-rgb", "--wbds-line",
    "--wbds-panel-opacity", "--wbds-task-panel-opacity", "--wbds-blur",
    "--wbds-focus-x", "--wbds-focus-y", "--wbds-art-home-opacity",
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
    if (document.querySelector(".wb-home-page, .main-content--welcome, .chat-container--welcome")) return "home";
    if (document.querySelector("[class*='settings'], [data-view-id*='settings']")) return "settings";
    if (document.querySelector(".chat-container:not(.chat-container--welcome), .detail-layout, .detail-panel")) return "task";
    return "shell";
  };

  const applyVariables = (root) => {
    const values = {
      "--wbds-bg-rgb": parseHex(colors.background, "#080b12"),
      "--wbds-panel-rgb": parseHex(colors.panel, "#101620"),
      "--wbds-panel-alt-rgb": parseHex(colors.panelAlt, "#182230"),
      "--wbds-accent-rgb": parseHex(colors.accent, "#9ad8ff"),
      "--wbds-text-rgb": parseHex(colors.text, "#eef7ff"),
      "--wbds-muted-rgb": parseHex(colors.muted, "#9eafbf"),
      "--wbds-line": String(colors.line || "rgba(154, 216, 255, 0.24)"),
      "--wbds-panel-opacity": String(clamp(numeric(effects.panelOpacity, 0.72), 0.25, 1)),
      "--wbds-task-panel-opacity": String(clamp(numeric(effects.taskPanelOpacity, 0.92), 0.6, 1)),
      "--wbds-blur": `${clamp(numeric(effects.blur, 18), 0, 40)}px`,
      "--wbds-focus-x": `${clamp(numeric(art.focusX, 0.72), 0, 1) * 100}%`,
      "--wbds-focus-y": `${clamp(numeric(art.focusY, 0.46), 0, 1) * 100}%`,
      "--wbds-art-home-opacity": String(clamp(numeric(art.homeOpacity, 0.96), 0, 1)),
      "--wbds-art-task-opacity": String(clamp(numeric(art.taskOpacity, 0.28), 0, 1)),
      "--wbds-art-settings-opacity": String(clamp(numeric(art.settingsOpacity, 0.12), 0, 1)),
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

    applyVariables(root);
    root.setAttribute("data-workbuddy-dream-skin", "active");
    root.setAttribute("data-wbds-appearance", detectAppearance());
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
