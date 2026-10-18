# CodexUsageStatus logo research

> Research-only note. No artwork or application code was changed in this pass.

## Scope and method

This review compares five first-party sources: two direct AI quota monitors and three mature macOS menu-bar/status-bar utilities. The goal is not to copy any existing mark, but to identify visual conventions that remain legible in a crowded 16–18 px menu-bar slot.

The preference for concepts 2, 7, and 8 is treated as a weak signal: it suggests comfort with balanced, geometric, status-oriented forms, but it does not determine the next design direction.

## Comparable products

| Product | Real usage scenario | Logo / menu-bar visual language | Implication for a small CodexUsageStatus icon |
| --- | --- | --- | --- |
| **CodexBar** | Keeps multiple AI coding-provider limits visible, including session/weekly windows and reset timing, so a developer can decide whether to start a long task. It supports one item per provider or a merged provider switcher. | The product explicitly describes its menu-bar icon as a “tiny usage meter.” Its documented renderer is an 18×18 template image; bar fill represents remaining percentage by default, and stale/error states can dim or add an incident indicator. This is literal status visualization rather than a decorative app emblem. [README](https://github.com/steipete/CodexBar) · [UI and icon specification](https://github.com/steipete/CodexBar/blob/main/docs/ui.md) | Usage should be encoded in the mark itself: an aperture, bar, gauge, or other measurable shape is more immediately legible than a generic AI spark. Keep the mark valid as a monochrome template image and reserve color for warning state. |
| **ClaudeBar** | Shows Claude session (5-hour), weekly, and weekly Opus limits without opening the dashboard; the popover adds progress bars and reset times. The menu bar exposes one primary percentage at a glance and refreshes periodically or when opened. | The compact identity is a small star-like glyph plus a percentage (`✳ 61%`), while the popover carries the detailed multi-window explanation. Its README emphasizes a native macOS design that adapts to light/dark mode, a launch-at-login toggle, and read-only usage access. [Repository README](https://github.com/ousid/claudebar) | A logo may carry a recognizable “source/product” personality, but the menu-bar state still needs an explicit numeric or progress cue. For CodexUsageStatus, the 5H/7D distinction should remain visible rather than collapsing to one headline percentage. |
| **iStat Menus** | A long-running system monitor used for continuous glanceable checks of CPU, memory, disk, network, battery, sensors, weather, and clocks; detailed menus are available on demand. It also offers a combined mode to save menu-bar space. | The visual system is a configurable family of compact metrics rather than one fixed symbol: users choose what appears, colors, order, spacing, and how much detail is shown. The product presents the menu bar as a dense dashboard, with the dropdown reserved for depth. [Official product page](https://bjango.com/mac/istatmenus/) · [Official help](https://weather.bjango.com/help/istatmenus7/welcome/) | Treat the logo as a compact semantic anchor in a dense ecosystem. It must survive adjacent text, battery, Wi‑Fi, and control-center icons without a capsule background or excessive color. |
| **Stats** | An open-source system monitor that replaces repeated Activity Monitor checks with live menu-bar readings for CPU, GPU, RAM, disk, network, sensors, battery, Bluetooth, and clocks. | Stats exposes a deliberately modular visual vocabulary: widgets can be a chart, number, gauge, dot, label, text, tachometer, or stack, and users can combine, reorder, and color them. The emphasis is on literal measurement primitives and user-selected density, not a single ornamental logo. [Official site](https://mac-stats.com/) · [Source repository](https://github.com/exelban/stats) | “Usage” is best communicated through a small measurement primitive: an arc, fill level, tick, or paired channels. The mark should be understandable even when the center number is too small or temporarily hidden. |
| **Bartender** | Used when a Mac has too many menu-bar items: it hides, reveals, searches, reorders, and conditionally shows items through triggers such as unplugging power, joining public Wi‑Fi, or entering a meeting. | Its current product language treats the menu bar as a constrained layout system: glass, pills, outline, gradient, solid, labels, symbols, adjustable spacing, and notch-aware hiding. The important design lesson is not a specific Bartender shape, but the need for a stable silhouette under different backgrounds and available widths. [Official product page](https://www.macbartender.com/) | Design for the worst case: a tiny, monochrome, partially crowded slot. Prefer a clear outer silhouette and negative space over fine detail; make a full-size app icon/wordmark a separate asset from the menu-bar glyph. |

## Reassessment of CodexUsageStatus

The current product is a passive, always-visible monitor for two remaining-quota windows: **5H** and **7D**. Its value is not “AI is running”; its value is “how much usable budget remains, and when will it reset?” That makes the product closer to a compact instrument panel than to a chatbot or coding mascot.

The current local design already has the right product constraints:

- two windows must be distinguishable without opening the menu;
- percentage is remaining quota, so a fuller shape means more headroom;
- normal state is neutral/template-tinted, with red reserved for below-20% urgency;
- the badge must work in both system appearances and beside unrelated macOS status items;
- the popover can explain reset times, while the menu-bar mark only needs to establish “usage monitor” immediately.

## Design language to carry forward

1. **Make measurement visible.** Use a shape with an interpretable amount—partial ring, segmented fill, paired lanes, or a bounded aperture. Avoid a standalone sparkle, robot, speech bubble, or abstract knot that could mean any AI product.
2. **Keep the two-window grammar.** The mark should have two related but separable channels, so 5H and 7D remain conceptually present even when labels are minimized.
3. **Use OpenAI-adjacent restraint without copying its mark.** The useful shared language is geometric construction, rounded transitions, balanced negative space, and a calm monochrome default—not the specific interlocking emblem, silhouette, or proportions of OpenAI branding.
4. **Separate brand mark from status glyph.** The app icon can have a richer, more ownable form; the menu-bar version should be a reduced template-safe core with no tiny text and no fragile interior detail.
5. **Make state secondary to identity.** Neutral appearance should be the default. Red can signal the actionable low-quota condition; avoid green/orange as persistent decoration because the app is meant to be quiet and glanceable.
6. **Validate at actual menu-bar size.** A concept is not successful because it looks good at 512 px. It should remain recognizable at 16–18 px, in both light and dark appearances, with the center number removed, and beside several other status icons.

## Directions for the next logo round

These are design directions only; no artwork was generated in this research pass.

- **Paired measurement mark:** two related apertures or channels, with clearly different scale/role but one coherent silhouette.
- **Quota instrument:** a single compact gauge-like form whose negative space implies remaining capacity, with a secondary division for the weekly window.
- **Usage pulse:** a restrained live-status form that suggests updating/measurement, but remains a quota indicator rather than a heartbeat or notification badge.
- **System-native abstraction:** a monochrome geometric mark optimized for template tinting, with the full-color app icon adding depth only outside the menu bar.

The strongest criterion for the next generation should be: **someone seeing the mark for the first time should infer “remaining usage/quota” before they infer “AI.”**

## Sources

- CodexBar: <https://github.com/steipete/CodexBar>
- CodexBar UI/icon details: <https://github.com/steipete/CodexBar/blob/main/docs/ui.md>
- ClaudeBar: <https://github.com/ousid/claudebar>
- iStat Menus: <https://bjango.com/mac/istatmenus/>
- iStat Menus help: <https://weather.bjango.com/help/istatmenus7/welcome/>
- Stats official site: <https://mac-stats.com/>
- Stats source repository: <https://github.com/exelban/stats>
- Bartender: <https://www.macbartender.com/>
