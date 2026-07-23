# Architecture

## Runtime flow

```text
signed WorkBuddy.app
  └─ WORKBUDDY_REMOTE_DEBUGGING_PORT + --remote-debugging-address=127.0.0.1
       └─ verified WorkBuddy main renderer target
            └─ CDP adds the theme runtime for the current and future documents
                 ├─ WorkBuddy CSS token bridge
                 ├─ wallpaper layer
                 ├─ WorkBuddy/OS light-dark appearance observer
                 └─ route-aware home/task/settings opacity
```

The launcher does not unpack, patch, replace, re-sign, or redistribute
`WorkBuddy.app` or `app.asar`. A full restore removes the injected runtime,
stops only the launchd jobs created by this project, and reopens the official
application without a debugging port.

## User theme flow

`Customize WorkBuddy Dream Skin.command` uses the native macOS file picker.
The selected image never leaves the machine: `sips` converts it to a bounded
JPEG, `write-theme.mjs` writes an `appearance: auto` theme, and both are stored
under `~/Library/Application Support/WorkBuddyDreamSkin`. Each import is kept in
`themes/`; the active copy lives in `current-theme/`, outside the replaceable
engine installation.

When a themed WorkBuddy session is already active, the apply script replaces
only the recorded injector launchd job and re-injects the new payload into the
same verified renderer. The WorkBuddy process and any task state stay intact.
If WorkBuddy was launched normally, the user must explicitly approve a normal
application restart before the theme is applied.

`appearance: auto` first reads WorkBuddy's native light/dark classes and theme
attributes, then falls back to `prefers-color-scheme`. Both DOM theme changes
and OS media-query changes schedule a new palette application. Light and dark
palettes have separate structural colors; wallpaper luminance never flips the
user's chosen UI appearance.

## Trust boundaries

- The application must have bundle ID `com.workbuddy.workbuddy`, verified nested
  code signatures, and Tencent Team ID `FN2V63AD2J`. The only permitted outer
  resource-seal exception is WorkBuddy 5.3.3's exact runtime-generated
  `@tencent/tencent-docs-ai-engine/.../editor_sdk.log` path; all other resource
  changes fail closed.
- CDP HTTP and WebSocket URLs must use loopback and the selected port.
- The Browser user agent must identify WorkBuddy.
- Only a `page` target titled `WorkBuddy` whose file URL ends in
  `/app.asar/renderer/index.html` is considered.
- The page must also expose `#root` and verified WorkBuddy shell markers.
- Login windows, browser previews, document webviews, and third-party content
  are never injection targets.

CDP has no authentication against another process running as the same local
user. Keep the themed session limited to trusted local software and use Restore
when it is not needed.

## Compatibility contract

`assets/selectors.json` is versioned independently from the theme. Required L0
and L1 selectors gate the main renderer; optional L2 selectors provide visual
polish. Prefer WorkBuddy's `--wb-*` design tokens and semantic BEM classes over
exact CSS Module hashes.

After every WorkBuddy update:

1. Run Verify.
2. Capture a text-free DOM fixture for home, task, settings, and preview states.
3. Compare required selector hits.
4. Update the contract only when the semantic UI actually changed.
