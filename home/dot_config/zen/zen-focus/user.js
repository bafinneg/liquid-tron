// Enable userChrome.css loading (Zen checks both pref variants)
user_pref("toolkit.legacyUserProfileCustomization.stylesheets", true);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Tron cyan tab indicators (Better Tab Indicators mod)
user_pref("uc.tabs.preferred_color", "custom");
user_pref("uc.tabs.custom_color_hex", "#0abdc6");

// UI + page zoom to compensate for 1.0x monitor scaling on 27" 4K side
// displays (FEAT-workspace-ux-overhaul Phase 0).
user_pref("layout.css.devPixelsPerPx", "1.5");

user_pref("security.enterprise_roots.enabled", true);

// FEAT-lt26r-3 OD-D (05 OD1 Z-A): Zen UI keeps its dark glass, pages render opaque (window rule 1.0).
// Installed Zen 1.19.8b-1 default is false (browser/omni.ja defaults/preferences/firefox.js:1739). Needs a Zen relaunch.
user_pref("zen.widget.linux.transparency", true);
