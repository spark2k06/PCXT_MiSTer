# EGA Traceability Checklist

> Clean-core note: older EGA task IDs in this file describe the historical
> coexistence port. For the `ega-mcga-clean-core` branch, use
> `EGA_CLEAN_CORE_SPEC.md`, `EGA_CLEAN_CORE_PLAN.md`, and
> `EGA_CLEAN_CORE_TASKS.md` as the active architecture source. CGA compatibility
> is now an EGA feature, not a separate CGA/HGC/Tandy coexistence target.

This checklist maps the EGA specification to implementation areas, current
evidence, and backlog task IDs. It is meant to answer two questions before each
change: where should the behavior live, and which task proves or completes it?

## Specification Coverage

| SPEC Area | Required Behavior | Current RTL / Asset Owner | Evidence | Remaining Tasks |
| --- | --- | --- | --- | --- |
| 3. I/O decode and port visibility | Decode EGA sequencer, graphics controller, attribute controller, CRTC, status, Misc Output, Feature Control, and DAC-visible ports. | `rtl/video/ega_top.v`, `rtl/video/ega_sequencer.v`, `rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_attrib_ctrl.v`, `rtl/video/UM6845R.v` | `EGA_IO_DECODE_AUDIT.md`; EGA-201, EGA-202 | EGA-504, EGA-505, EGA-507 |
| 3.1 Color/mono CRTC/status selection | Misc Output bit `0` selects active `3D4/3D5/3DA` or `3B4/3B5/3BA` range. | `rtl/video/ega_top.v` | EGA-202 | EGA-208, EGA-507 |
| 4.1 Attribute Controller | Address/data flip-flop, palette registers, Mode Control, Overscan, Plane Enable, PEL panning, Color Select, status-read reset. | `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_top.v` | `EGA_ATTR_CTRL_AUDIT.md`; EGA-203 | EGA-501..EGA-507 |
| 4.2 Sequencer | Reset, Clocking Mode, Map Mask, Character Map Select, Memory Mode, chain-2 write, odd/even/extended-memory control. | `rtl/video/ega_sequencer.v`, `rtl/video/ega_vram.v`, future text renderer | `EGA_SEQUENCER_AUDIT.md`; EGA-205 | EGA-208, EGA-405, EGA-604 |
| 4.3 Graphics Controller | Set/reset, enable set/reset, compare, rotate/ROP, read map, read/write modes, misc, color don't care, bit mask. | `rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_vram.v`, `rtl/KFPC-XT/HDL/Peripherals.sv` | `EGA_GFX_CTRL_AUDIT.md`; EGA-206 | EGA-208, EGA-403, EGA-404 |
| 4.4 Misc Output | IO select, clock select, page select, sync polarities, readback, switch-sense side effects. | `rtl/video/ega_top.v` | `EGA_MISC_OUTPUT_AUDIT.md`; EGA-204 | EGA-504, EGA-505 |
| 4.5 CRTC registers | Register storage, protected writes, vertical overflow composition, start/cursor address, line compare, reset/display enable. | `rtl/video/UM6845R.v`, `rtl/video/ega_top.v` | EGA-207 | EGA-301..EGA-308 |
| 5. CPU VRAM access | Planar aperture decode, memory-map selection, odd/even, chain-2, page select, read/write modes, latches. | `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`, `rtl/video/ega_vram.v` | EGA-101..EGA-108 | EGA-109, EGA-110, EGA-801 |
| 6. Display address generation | Render-side address remap, start address, scanline row advance, split/line compare, frame latching. | `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`, `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv` | Partial CRTC RTL only | EGA-303..EGA-308 |
| 7. Graphics pixel pipeline | Planar-to-pixel conversion, graphics mode selection, horizontal panning, CGA-compatible 2bpp, blink, blanking, plane enable. | `rtl/video/ega_pixel.v`, `rtl/video/ega_vgaport.v`, `rtl/video/ega_top.v` | Current RTL plus SPEC gap notes | EGA-401..EGA-409 |
| 8. Palette and RGB output | Attribute palette indirection, 16/64-color lookup, overscan/border, RGB conversion. | `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_vgaport.v`, `rtl/video/ega_top.v` | `EGA_ATTR_CTRL_AUDIT.md`; `EGA_SMOKE_CHECKLIST.md` | EGA-501..EGA-503 |
| 9. Status and timing side effects | Input Status #1 display/retrace bits, attribute flip-flop reset, switch-sense bits, blink cadence. | `rtl/video/ega_top.v`, `rtl/video/UM6845R.v`, future shared blink generator | EGA-203, EGA-204 | EGA-504, EGA-506, EGA-507 |
| 10. Text rendering | Text fetches, font plane, character map select, attributes, underline, cursor, 9th-dot line graphics, text panning. | Future text renderer plus `rtl/video/ega_sequencer.v`, `rtl/video/UM6845R.v` | Current ownership identified only | EGA-601..EGA-610 |
| 11. Integration | BIOS ROM path, always-on EGA activation, CGA-compatible behavior through EGA, removed legacy video gates, smoke flows. | `egabios.rom`, `egabios.asm`, `rtl/KFPC-XT/HDL/Peripherals.sv`, project config | `EGA_SMOKE_CHECKLIST.md`; `EGA_CLEAN_CORE_TASKS.md` | ECC-601..ECC-604, ECC-701..ECC-703 |
| 12. Verification | Reference models, register tests, CRTC address tests, pixel/text tests, integrated smoke and game matrix. | `rtl/KFPC-XT/TESTBENCH/`, future reference helpers, smoke docs | `TEST_TOOLS.md`; `EGA_SMOKE_CHECKLIST.md` | EGA-208, EGA-801..EGA-807 |

## x86Box Reference Anchors

| Behavior | x86Box Source | Local Porting Target | Task IDs |
| --- | --- | --- | --- |
| EGA register I/O and CRTC protection | `x86_src/video/vid_ega.c` | `ega_top.v`, `UM6845R.v`, register testbench | EGA-201..EGA-208 |
| CPU planar VRAM semantics | `x86_src/video/vid_ega.c`, render/write helper paths | `ega_vram.v`, `ega_vram_bram_frontend.sv`, `Peripherals.sv` | EGA-101..EGA-110 |
| Render address remapping | `x86_src/video/vid_ega_render.c` | `UM6845R.v`, `ega_top.v`, scanout-side VRAM fetch | EGA-303, EGA-308 |
| Graphics pixel conversion | `x86_src/video/vid_ega_render.c` | `ega_pixel.v`, `ega_vgaport.v` | EGA-401..EGA-409 |
| Text rendering and attributes | `x86_src/video/vid_ega_render.c` | Future text renderer, `ega_attrib_ctrl.v`, `UM6845R.v` | EGA-601..EGA-610 |
| Palette and status behavior | `x86_src/video/vid_ega.c` | `ega_attrib_ctrl.v`, `ega_vgaport.v`, `ega_top.v` | EGA-501..EGA-507 |

## Open Verification Blockers

| Blocker | Impact | Tracking |
| --- | --- | --- |
| No standalone HDL simulator is installed (`vsim`, `iverilog`, `verilator` unavailable). | EGA-109, EGA-208, and later unit-test tasks cannot be executed end-to-end locally. | `TEST_TOOLS.md`; EGA-002 remains open. |
| Game disk-image provenance is not fully recorded beyond `games/PCXT/hd_image.zip`. | Game smoke failures are not reproducible unless each image/checksum is logged. | `EGA_SMOKE_CHECKLIST.md`; EGA-807 |
| Text renderer ownership is still future-work. | Sequencer Character Map Select and text attribute semantics can be stored but not fully rendered. | EGA-601..EGA-610 |

## Maintenance Rules

- When a task is completed, add or update the evidence column with the audit,
  testbench, RTL commit, or smoke checklist that proves it.
- When a SPEC behavior is split, keep the original row and list the new task IDs
  rather than deleting the requirement.
- When x86Box behavior is intentionally not ported, record the deviation in
  EGA-903 before treating the row as closed.
