# EGA Intentional Deviations

This document records behavior that is intentionally outside the first PCXT
EGA port, and separates those non-goals from unresolved or unverified behavior.
The implementation target remains base IBM EGA compatibility as described in
`SPEC.md`, not every adapter variant modeled by x86Box.

## Confirmed Non-Goals

The following x86Box-supported extensions are intentionally not required for
the first complete PCXT EGA port:

| Area | Decision | Rationale |
| --- | --- | --- |
| Compaq EGA color mux and monitor ID ports | Not implemented. | This is adapter-specific behavior beyond base IBM EGA. Attribute Controller register `12h[5:4]` is therefore not used for Compaq status/color mux behavior. |
| Chips & Technologies SuperEGA registers | Not implemented. | Extended SuperEGA behavior is outside the base PCXT target. |
| ATI EGA Wonder EEPROM and extended registers | Not implemented. | These are vendor-extension paths, not required for IBM EGA software compatibility. |
| JEGA/JVGA behavior | Not implemented. | Japanese EGA/VGA variants are outside the current scope. |
| VGA RAMDAC palette behavior | Not implemented. | Base EGA uses the digital EGA palette path. Reads from `3C7h..3C9h` currently return `00h`, and EGA RGB output is generated from EGA palette state rather than VGA DAC RAM. |
| Exact analog monitor overscan geometry | Not required. | The port must preserve active display, border color, blanking/status behavior, and stable MiSTer output. It does not need to reproduce analog monitor border dimensions exactly. |

## Deliberate PCXT/MiSTer Adaptations

The following differences are intentional integration choices, not open bugs by
themselves:

- The EGA output path is adapted into the existing PCXT/MiSTer video pipeline.
  Internal EGA timing, display-enable, blanking, border color, and status
  signals remain the compatibility boundary; exact analog monitor framing is
  not the target.
- Attribute Controller register `14h` Color Select is stored and readable, but
  it does not alter the effective base IBM EGA palette. This matches the
  current x86Box base IBM EGA behavior used by `SPEC.md`.
- The Sequencer CPU access-slot signal is exported into the VRAM frontend as a
  timing hint, but the current BRAM implementation intentionally does not gate
  CPU transfers with it. CPU and CRT paths use independent ports, and PCXT bus
  ready behavior is kept stable through the frontend state machine.

## Not Classified As Intentional Deviations

The following remain verification topics until platform smoke testing provides
pass/fail evidence:

- Visual correctness of BIOS boot, DOS text, mode `03h`, mode `0Dh`, mode
  `0Eh`, and mode `10h`.
- Behavior of known EGA games, especially detection paths, smooth scrolling,
  split-screen behavior, and masked sprite drawing.
- CGA, HGC, and Tandy non-regression results with EGA enabled and disabled.
- Any mismatch found by the integrated `EGA_CHIPSET_SMOKE` flow once a
  standalone HDL simulator is available.

If one of these topics fails during EGA-705 or later release-candidate testing,
it should become a bug or follow-up task unless it is explicitly reclassified
here with a compatibility rationale.

## Release Rule

Do not use this document to hide incomplete base IBM EGA behavior. A behavior
may be treated as intentional only when it is:

1. Outside the base IBM EGA target, or
2. A MiSTer integration adaptation that preserves the observable compatibility
   contract, and
3. Documented above with enough rationale for future regression triage.
