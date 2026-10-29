# PATTERNS — adopted patterns and their origins

## Tron-sweep two-layer gradient panning
- **What:** Atmospheric background animation using two horizontally-panning gradient layers (a 2px cyan band at 60% alpha and a full-height glow at 12% alpha) on a 45-second linear loop.
- **Source:** `machines/7800x/dotfiles/waybar/.config/waybar/style.css` — the existing `@keyframes tron-sweep` CSS animation and its `background-image` / `background-size: 400%` gradient definitions.
- **Why we adopted:** Visual parity with the previous waybar bar (archived 2026-05-02; MOCR-Q is the successor). The tron-sweep is the bar's signature atmospheric motion; MOCR-Q must preserve it.
- **What we changed:** CSS `background-position` animation replaced with a single QML `sweepProgress` property (0→1) driving both layers' x-offset via binding. 400%-wide gradients are literal 4x-width QML Rectangles inside clipped Items. Both layers bind to the same progress property to guarantee phase sync, which CSS achieves implicitly via a single `animation` declaration. `Easing.Linear` used directly (not `Motion.linear` bezier) since this is a constant-speed loop, not a motion-vocabulary animation.

## Single-process stats polling
- **What:** A single bash script reads /proc/stat, /proc/meminfo, /sys/class/hwmon, and /proc/net/dev in one execution, outputting tagged lines (CPU:, MEM:, TMP:, NET:) parsed line-by-line via SplitParser.
- **Source:** Common pattern in system monitoring tools (conky, polybar scripts). Waybar uses native C modules for the same data.
- **Why we adopted:** Spawning four separate Process objects per poll cycle (one per metric) would quadruple fork overhead. A single bash invocation reads all kernel-cached files in sub-millisecond time.
- **What we changed:** Output uses a tagged-line protocol instead of JSON, parsed by SplitParser's per-line onRead callback. hwmon path is discovered dynamically at startup (k10temp sensor index is not stable across reboots).

## Module wrapping via ModuleContainer
- **What:** Every bar module wraps its content in a ModuleContainer component that provides shared chrome (1px fg_dark left border, 10px horizontal padding).
- **Source:** Waybar's CSS `#module-name { border-left: 1px solid; padding: 0 10px; }` pattern applied identically across all modules.
- **Why we adopted:** Consistent divider and padding across all modules without repeating geometry constants in each module file.
- **What we changed:** QML Item-based component with a contentItem alias, rather than CSS class inheritance. Each module declares its content as children of the contentItem property.

## wpctl volume polling over Pipewire QML API
- **What:** Volume module polls `wpctl get-volume @DEFAULT_AUDIO_SINK@` via Process instead of using Quickshell.Services.Pipewire's reactive properties.
- **Source:** Waybar's pulseaudio module uses native PulseAudio/PipeWire bindings; our approach matches waybar's `on-click: wpctl` pattern.
- **Why we adopted:** Quickshell 0.2.1's `Pipewire.defaultAudioSink` returns a PwNodeIface proxy that never reaches `ready` state — `audio.volume` returns NaN, `audio.volumes` is empty. The QML API appears to require explicit node binding that isn't documented.
- **What we changed:** 1-second wpctl polling replaces reactive property binding. Trades sub-millisecond reactivity for reliable volume reads. Phase 7c's VolumePicker may revisit the QML API if upstream fixes the initialization issue.

## PopupWindow-based popovers with HyprlandFocusGrab
- **What:** Base `Popover.qml` component extending `PopupWindow`, using `HyprlandFocusGrab` for Wayland-native click-outside dismissal. Chrome fade animated on the inner Rectangle, not the Wayland surface itself.
- **Source:** Quickshell's `PopupWindow` API (anchor-based positioning) + `Quickshell.Hyprland._FocusGrab/HyprlandFocusGrab` (grab-based dismiss). No external reference repo pattern — designed from the qmltypes API surface.
- **Why we adopted:** On Wayland, transparent click-capture overlays don't work for popups because `PopupWindow` creates a separate compositor surface outside the parent scene graph. `HyprlandFocusGrab` is the compositor-native solution: it tells Hyprland "these windows own focus; clicking elsewhere clears the grab," which triggers `onCleared` for dismissal.
- **What we changed:** Property name is `popoverContent` (not `contentItem`) to avoid shadowing `ProxyWindowBase.contentItem`. Fade animation targets the chrome Rectangle's opacity rather than the window-level opacity (which is compositor-controlled on Wayland). Modules hosting popovers receive `parentBar` property from Bar.qml for the anchor.window binding.

## Sparkline via Shape + PathPolyline
- **What:** `Sparkline.qml` renders a 60-point line chart using `QtQuick.Shapes` with `Shape` > `ShapePath` > `PathPolyline`, auto-scaled to component bounds.
- **Source:** Standard Qt Quick Shapes API (available since Qt 6.6, confirmed on Qt 6.11).
- **Why we adopted:** Declarative and reactive — `PathPolyline.path` re-evaluates when the bound property changes, no `requestPaint()` calls needed (unlike Canvas). Cleaner integration with QML property bindings.
- **What we changed:** Two ShapePaths per Shape: one for the filled area under the line (translucent), one for the line stroke. Fill path is the line points + two extra points closing to the bottom corners.

## ShaderEffect with pre-compiled QSB fragment shader
- **What:** `LogomarkWidget.qml` renders a GLSL 4.40 fragment shader via `ShaderEffect` with `fragmentShader: Qt.resolvedUrl("../shaders/logomark.frag.qsb")`, where the `.qsb` file is pre-compiled offline from `logomark.qs.frag`.
- **Source:** Qt Quick `ShaderEffect` API requires `.qsb` (Qt Shader Baker) format since Qt 6 — raw GLSL strings no longer supported at runtime. Offline compilation via `qsb --glsl "300es,310es,320es,330,440" --hlsl 50 --msl 12 -o logomark.frag.qsb logomark.qs.frag`. ES variants are mandatory because Quickshell's Qt scene graph on this NVIDIA/Wayland stack creates an OpenGL ES context.
- **Why we adopted:** MOCR-Q runs on a 4090 (GLSL 4.6) but Qt compiles to SPIR-V → GLSL adapters via `qsb`. Pre-compiling avoids runtime compilation latency and catches shader syntax errors at build time.
- **What we changed:** Three files co-exist in `shaders/`: `logomark.qs.frag` (GLSL 4.40, layout qualifiers, Qt6/ShaderEffect source — input to `qsb`), `logomark.frag.qsb` (compiled binary — sole runtime input to `ShaderEffect`), and `logomark.frag` (GLSL 3.30, no layout qualifiers — the moderngl dialect used by `tools/logomark/render.py` for offline PNG generation). The `.frag` and `.qs.frag` files are kept in sync on geometry/math changes; they differ only in dialect (uniform block vs bare uniforms, layout qualifiers vs none).

## WlrLayer.Overlay with visible=false for on-demand overlays
- **What:** Large overlay components (`Overview.qml`, `CursorPulse.qml`, `SplashOverlay.qml`, `UnlockOverlay.qml`) are always instantiated but stay hidden via `visible: false` until triggered. They use `WlrLayershell.layer: WlrLayer.Overlay` with `exclusiveZone: -1`.
- **Source:** Quickshell's layer-shell convention; established in `FEAT-workspace-overview` (Overview.qml) and propagated to subsequent overlays.
- **Why we adopted:** Layer-shell windows cannot be dynamically created/destroyed cleanly — the compositor handles surface lifecycle and deferred creation introduces race conditions during startup. Pre-creating with `visible: false` costs zero render work when hidden.
- **What we changed:** Each overlay manages its own visibility toggle. `exclusiveZone: -1` prevents the overlay from pushing the bar or other exclusive-zone surfaces. `WlrKeyboardFocus.OnDemand` is used for overlays that need keyboard input (Overview); `WlrKeyboardFocus.None` for purely visual overlays (CursorPulse, SplashOverlay).

## Reference repos not available
- **Note:** `dots-hyprland`, `DankMaterialShell`, and `caelestia-dots` were not cloned locally at the time of Phase 3/4 implementation (2026-04-12). The waybar config/CSS was the sole reference for module layout and formatting. If these repos are cloned for future phases, update this file with any patterns adopted from them.
