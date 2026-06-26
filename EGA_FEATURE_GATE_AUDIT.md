# EGA Menu And Feature-Gate Integration Audit

## Scope

This audit verifies how the current PCXT integration gates the EGA feature at
compile time and at runtime through the MiSTer menu.

Reviewed files:

- `PCXT.sv`
- `files.qip`
- `rtl/KFPC-XT/HDL/Chipset.sv`
- `rtl/KFPC-XT/HDL/Peripherals.sv`

## Compile-Time Gate

`PCXT.sv` defines `ENABLE_EGA` to `1` only when the macro has not already been
provided by the build:

```verilog
`ifndef ENABLE_EGA
`define ENABLE_EGA 1
`endif
```

The EGA menu entry is conditional:

```verilog
localparam CONF_STR_EGA = (`ENABLE_EGA ? "P1oL,EGA Gate,Disabled,Enabled;" : "");
```

When `ENABLE_EGA=0`, the menu does not expose the EGA gate and:

- `ega_enabled` is forced to `1'b0`.
- `enable_a000h` receives `a000h & ~ega_enabled`, so the A000 UMB path is not
  blocked by EGA.
- `status_menumask` exposes both EGA-dependent menu bits as zero because it is
  derived from `ega_enabled`.

`files.qip` still includes the EGA implementation files through
`rtl/video/video.qip` and explicitly includes `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
This means `ENABLE_EGA=0` is currently a functional integration gate, not a
source-file exclusion gate. Quartus Analysis & Elaboration accepts that
configuration.

## Runtime Menu Gate

With `ENABLE_EGA=1`, `PCXT.sv` maps the menu bit to:

```verilog
wire ega_enabled = `ENABLE_EGA ? status[53] : 1'b0;
```

This value is passed into `CHIPSET`, then into `PERIPHERALS`.

In `Peripherals.sv`, EGA CPU memory selection requires both compile-time and
runtime enables:

```verilog
wire ega_mem_select = `ENABLE_EGA
                    ? (~iorq && ~address_enable_n && ega_enabled && enable_cga
                       && ega_memory_window_select(address, ega_mem_map_sel_cfg))
                    : 1'b0;
```

Therefore, when the menu gate is disabled:

- EGA VRAM CPU read/write requests are inactive because they are derived from
  `ega_mem_select`.
- EGA VRAM does not drive CPU read data because the data bus mux requires
  `` `ENABLE_EGA && ega_mem_select && ~memory_read_n ``.
- CGA/Tandy/HGC memory selects are not suppressed by EGA because they are
  blocked only by `~ega_mem_select`.
- `ega_memory_access_ready` remains ready because `ega_vram_cpu_cycle` is false.

## Video Output Gate

The EGA runtime enable is synchronized into the CGA/video clock domain through
`ega_enabled_cga_ff_1` and `ega_enabled_cga_ff_2`. `ega_top` receives
`ega_enabled_cga_ff_2`.

The visible RGB path selects EGA only when `ega_rgb_active` is true:

```verilog
assign VGA_R = swap_video_sel ? R_HGC : (ega_rgb_active ? R_EGA : (`ENABLE_CGA ? R_CGA : 6'd0));
assign VGA_G = swap_video_sel ? G_HGC : (ega_rgb_active ? G_EGA : (`ENABLE_CGA ? G_CGA : 6'd0));
assign VGA_B = swap_video_sel ? B_HGC : (ega_rgb_active ? B_EGA : (`ENABLE_CGA ? B_CGA : 6'd0));
```

The previous EGA activation audit verified that `ega_top` gates
`ega_rgb_active` with its `ega_enabled` input. Combined with the synchronized
runtime gate above, disabling EGA leaves the visible output on the CGA/HGC path.

One implementation detail remains: `ega_top` and `ega_vram_bram_frontend` are
still instantiated when `ENABLE_EGA=0`. Their externally observable CPU and
video effects are gated off, but this does not reduce synthesis source scope or
resource usage unless Quartus optimizes the inactive logic away.

## Verification

Quartus Analysis & Elaboration was run for both configurations:

- Default build, `ENABLE_EGA=1`: passed with 0 errors and 249 warnings.
- Disabled build, `--verilog_macro="ENABLE_EGA=0"`: passed with 0 errors and
  249 warnings.

Generated Quartus artifacts were removed after verification.

## Result

No RTL changes are required for functional menu and compile-time gating.

The current integration behaves as expected:

- EGA enabled build exposes the menu gate and allows runtime EGA activation.
- EGA disabled build hides the menu gate and forces EGA integration inactive.
- Runtime-disabled EGA does not select EGA memory, does not stall the CPU bus,
  does not drive CPU read data, and does not select EGA RGB output.
