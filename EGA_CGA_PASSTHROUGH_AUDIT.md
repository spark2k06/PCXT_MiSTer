# EGA CGA Passthrough Dependency Audit

This audit supports `ECC-201` in the clean EGA core refactor. It records every
`rtl/video/ega_top.v` dependency on the temporary `cga_passthrough` instance and
classifies the replacement needed before the instance can be removed.

## Scope

- Audited file: `rtl/video/ega_top.v`.
- Target task: `ECC-201 - Audit ega_top CGA Passthrough Dependencies`.
- Follow-up removal tasks: `ECC-202`, `ECC-301`, `ECC-302`, and `ECC-303`.

## Dependency Inventory

| Signal or Group | Current Source | Current Use | Classification | Replacement Plan |
| --- | --- | --- | --- | --- |
| `cga_clkdiv` | `cga_passthrough.clkdiv` | Drives top-level `clkdiv` and derives `ce_pix`. | Needs EGA default. | Generate an EGA-owned pixel divider from `clk`, seeded to the current low-resolution default until sequencer clocking fully owns it. |
| `cga_bus_rdy` | `cga_passthrough.bus_rdy` | Drives `bus_rdy`. | Removable/default. | Drive ready from an EGA-owned default because current CGA passthrough does not provide active wait behavior in this integration. |
| `cga_bus_out` | `cga_passthrough.bus_out` | Final fallback in `ega_bus_out_mux`. | Removable. | Remove CGA bus read fallback; unclaimed EGA reads should return `8'h00` or the existing explicit EGA register result. |
| `cga_bus_dir` | `cga_passthrough.bus_dir` | ORed into `bus_dir` when EGA is enabled; sole bus direction when disabled. | Removable. | Drive `bus_dir` from `ega_bus_dir_sel` only; EGA is always enabled after `ECC-101`. |
| `cga_ram_we_l` | `cga_passthrough.ram_we_l` | Output fallback when EGA display is not selected. | Removable. | Drive inactive external CGA RAM write high. EGA VRAM writes are already handled outside this output. |
| `cga_ram_a` | `cga_passthrough.ram_a` | Output fallback when EGA display is not selected. | Removable. | Drive inactive address to zero once no external CGA display RAM path remains. |
| `cga_hsync`, `cga_dbl_hsync` | CGA timing/scandoubler | Fallback sync before `ega_display_sel`. | Needs EGA default. | Use EGA CRTC/reset timing or an explicit EGA pre-BIOS timing default. No CGA timing fallback should remain. |
| `cga_vsync` | CGA timing | Fallback sync before `ega_display_sel`. | Needs EGA default. | Use EGA-owned sync. |
| `cga_hblank`, `cga_vblank`, `cga_vblank_border` | CGA timing | Fallback blanking and activation edge source. | Needs EGA default. | Use EGA CRTC vertical blank for activation and output blanking. `cga_vblank_rise` must become EGA-owned. |
| `cga_std_hsyncwidth` | CGA timing | Fallback `std_hsyncwidth`. | Needs EGA default. | Report standard EGA hsync-width comparison directly from EGA CRTC width. |
| `cga_de_o` | CGA display enable | Fallback display enable before `ega_display_sel`. | Needs EGA default. | Drive EGA display enable or explicit inactive display state. |
| `cga_video`, `cga_dbl_video`, `cga_comp_video` | CGA pixel path | Fallback pixels before `ega_display_sel`. | Needs EGA default. | Drive EGA pixels when active, otherwise explicit blank EGA output. |
| `cga_grph_mode`, `cga_hres_mode` | CGA mode decode | Fallback mode status before `ega_display_sel`. | Needs EGA default/status. | Drive mode outputs from EGA sequencer/graphics-controller state. |
| `cga_tandy_color_16` | CGA/Tandy status | Fallback Tandy color status. | Removable. | Drive `tandy_color_16` low in the clean EGA core. |
| `cga_vblank_q`, `cga_vblank_rise` | Local registers derived from `cga_vblank` | Arms `ega_video_active` after a CGA vertical blank edge. | Needs EGA default. | Replace with EGA vertical blank edge so activation is independent of CGA timing. |

## Minimum Pre-Removal Work

Before deleting `cga_passthrough`, `ega_top` needs these EGA-owned replacements:

1. Pixel clock/divider ownership for `clkdiv` and `ce_pix`.
2. A reset/pre-BIOS timing path that produces stable EGA sync, blanking, and
   display-enable signals before BIOS programming.
3. An EGA vertical blank edge for `ega_video_active` arming.
4. Removal of CGA bus read/write fallback behavior from `bus_out`, `bus_dir`,
   `bus_rdy`, `ram_we_l`, and `ram_a`.
5. EGA-owned mode/status outputs for `grph_mode`, `hres_mode`, and
   `std_hsyncwidth`.
6. Explicit inactive EGA output values for RGB/indexed pixels and blanking.

## Current Migration Debt

`cga_passthrough` remains instantiated after `ECC-201` only as transition debt.
It must not be treated as the target compatibility mechanism. CGA-compatible
software behavior must be preserved through EGA-owned text, graphics, CRTC,
attribute, sequencer, graphics-controller, and VRAM behavior.
