derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# Clocks - PLL principal (Chipset/SDRAM domain)
set CLOCK_CORE      {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set CLOCK_CHIP      {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}
# Clocks - PLL video domain (precise frequencies)
set CLOCK_VIDEO_BASE   {emu|pll_system_inst|pll_system_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLOCK_VIDEO_X2   {emu|pll_system_inst|pll_system_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLOCK_VIDEO_OUT_PS {emu|pll_system_inst|pll_system_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
set CLOCK_HDMI      {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set CLOCK_H2F       {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}
# Derived clocks (from PLL video domain)
set CLOCK_14_318    {emu:emu|clk_14_318|q}

# clk_14_318 derives from clk_28_636 (PLL video - precise frequency)
create_generated_clock -name clk_14_318 -source [get_pins $CLOCK_VIDEO_BASE] -divide_by 2 [get_pins $CLOCK_14_318]
create_generated_clock -name SDRAM_CLK -source [get_pins $CLOCK_CHIP] [get_ports { SDRAM_CLK }]
create_clock -name VCLK_SDIO -period 20.000

# SPLASH
set_false_path -to [get_registers {emu:emu|splash_off}]

# CDC: PLL principal (Chipset) <-> PLL video (CPU/Video) - asynchronous clock domains
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks $CLOCK_VIDEO_BASE]
set_false_path -from [get_clocks $CLOCK_VIDEO_BASE] -to [get_clocks $CLOCK_CHIP]
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks $CLOCK_VIDEO_X2]
set_false_path -from [get_clocks $CLOCK_VIDEO_X2] -to [get_clocks $CLOCK_CHIP]
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks $CLOCK_VIDEO_OUT_PS]
set_false_path -from [get_clocks $CLOCK_VIDEO_OUT_PS] -to [get_clocks $CLOCK_CHIP]
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks clk_14_318]
set_false_path -from [get_clocks clk_14_318] -to [get_clocks $CLOCK_CHIP]

set_false_path -from [get_clocks $CLOCK_CORE] -to [get_clocks $CLOCK_VIDEO_BASE]
set_false_path -from [get_clocks $CLOCK_VIDEO_BASE] -to [get_clocks $CLOCK_CORE]
set_false_path -from [get_clocks $CLOCK_CORE] -to [get_clocks $CLOCK_VIDEO_X2]
set_false_path -from [get_clocks $CLOCK_VIDEO_X2] -to [get_clocks $CLOCK_CORE]
set_false_path -from [get_clocks $CLOCK_CORE] -to [get_clocks $CLOCK_VIDEO_OUT_PS]
set_false_path -from [get_clocks $CLOCK_VIDEO_OUT_PS] -to [get_clocks $CLOCK_CORE]
set_false_path -from [get_clocks $CLOCK_CORE] -to [get_clocks clk_14_318]
set_false_path -from [get_clocks clk_14_318] -to [get_clocks $CLOCK_CORE]

# HDMI_TX can switch at run time between the scaler's HDMI clock and the
# direct-video clock.  They are independent PLL domains.
set_false_path -from [get_clocks $CLOCK_HDMI] -to [get_clocks $CLOCK_VIDEO_OUT_PS]
set_false_path -from [get_clocks $CLOCK_VIDEO_OUT_PS] -to [get_clocks $CLOCK_HDMI]

# In analog-video mode these pins are driven by the video clock rather than
# the SDIO interface, so the virtual SDIO receiver clock is not applicable.
set_false_path -from [get_clocks $CLOCK_VIDEO_OUT_PS] -to [get_clocks VCLK_SDIO]
set_false_path -from [get_clocks $CLOCK_HDMI] -to [get_clocks VCLK_SDIO]

# Explicit retime constraints for the final HDMI output stage.
set_max_delay -from [get_clocks $CLOCK_VIDEO_BASE]   -to [get_clocks $CLOCK_VIDEO_OUT_PS] 17.500

# VIDEO
# NOTE: If the system clock and video clock are synchronous, the following description is not necessary.
set VIDEO_TO_SYSYEM_DELAY 10

# The video status feedback travels through the top-level HPS bus loopback.
# Its clock is the forwarded video clock, but TimeQuest cannot derive that
# relationship through the inout bus; retain the established CDC bound.
set_max_delay -from [get_clocks $CLOCK_VIDEO_OUT_PS] -to [get_clocks $CLOCK_H2F] $VIDEO_TO_SYSYEM_DELAY
set_max_delay -from [get_clocks $CLOCK_HDMI] -to [get_clocks $CLOCK_H2F] $VIDEO_TO_SYSYEM_DELAY

# pll_hdmi_adj explicitly synchronizes this frame marker into FPGA_CLK1_50.
set_false_path -from [get_registers {pll_hdmi_adj:pll_hdmi_adj|i_vss_delay}] \
              -to   [get_registers {pll_hdmi_adj:pll_hdmi_adj|ivss}]

# These reset synchronizers assert asynchronously and release on their local
# clocks.  Do not analyze recovery to their asynchronous assertion inputs.
set_false_path -to [get_registers {emu:emu|video_retime_reset_sync[*] \
                                   emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_reset_clock_sync[*] \
                                   emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_reset_video_sync[*]}]

# ascal contains equivalent per-clock reset-release registers.
set_false_path -to [get_registers {ascal:ascal|i_reset_na \
                                   ascal:ascal|o_reset_na \
                                   ascal:ascal|avl_reset_na}]

set_false_path -to [get_registers  {emu:emu|scale_video_ff[*] \
                                    emu:emu|screen_mode_video_ff[*] \
                                    emu:emu|border_video_ff \
                                    emu:emu|VIDEO_ARX[*] \
                                    emu:emu|VIDEO_ARY[*]}]

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_address[*]}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_address_sync1[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_data[*]}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_data_sync1[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_write_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_write_n_sync1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_read_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_read_n_sync1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_address_enable_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_address_enable_n_sync1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|EGA_IO_DOUT_SYNC1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|EGA_IO_OE_SYNC1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|hps_io:hps_io|video_calc:video_calc|vid_hcnt[*]   \
                                    emu:emu|hps_io:hps_io|video_calc:video_calc|vid_nres[*]   \
                                    emu:emu|hps_io:hps_io|video_calc:video_calc|vid_vcnt[*]}] \
              -to   [get_registers {emu:emu|hps_io:hps_io|video_calc:video_calc|dout[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|scale_video_ff[*]}] \
              -to   [get_registers {sl_r[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|swap_video_buffer_2}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -to   [get_registers {emu:emu|video_pause_core_buf}] $VIDEO_TO_SYSYEM_DELAY

#
set_max_delay -from [get_registers {osd:vga_osd|info       \
                                    osd:vga_osd|infoh[*]   \
                                    osd:vga_osd|osd_h[*]   \
                                    osd:vga_osd|osd_w[*]}] \
              -to   [get_registers {osd:vga_osd|osd_de[*]  \
                                    osd:vga_osd|osd_hcnt2[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {osd:vga_osd|osd_enable}] \
              -to   [get_registers {osd:vga_osd|osd_en[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {lowlat}]    \
              -to   [get_registers {ascal:ascal|i_mode[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {LFB_FLT}]   \
              -to   [get_registers {ascal:ascal|i_mode[2]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {LFB_EN}]    \
              -to   [get_registers {hmaxi[*]    \
                                    hmini[*]    \
                                    state[0]    \
                                    state[1]    \
                                    state[2]    \
                                    vmaxi[*]    \
                                    vmini[*]    \
                                    ascal:ascal|i_mode[2]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {FREESCALE}] \
              -to   [get_registers {state[0]    \
                                    state[1]    \
                                    state[2]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {HDMI_PR}]   \
              -to   [get_registers {videow[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {cfg_done}]                              \
              -to   [get_registers {pll_hdmi_adj:pll_hdmi_adj|i_delay[*]    \
                                    pll_hdmi_adj:pll_hdmi_adj|i_de2         \
                                    pll_hdmi_adj:pll_hdmi_adj|i_line[*]     \
                                    pll_hdmi_adj:pll_hdmi_adj|i_linecpt[*]  \
                                    pll_hdmi_adj:pll_hdmi_adj|i_vss_delay   \
                                    pll_hdmi_adj:pll_hdmi_adj|i_vss2}] $VIDEO_TO_SYSYEM_DELAY

# SDIO
set_input_delay -clock { VCLK_SDIO } -max 10 [get_ports { SDIO_DAT[*] SDIO_CMD }]
set_input_delay -clock { VCLK_SDIO } -min 5 [get_ports { SDIO_DAT[*] SDIO_CMD }]
set_output_delay -clock { VCLK_SDIO } -max 5 [get_ports { SDIO_DAT[*] SDIO_CMD SDIO_CLK }]
set_output_delay -clock { VCLK_SDIO } -min 0 [get_ports { SDIO_DAT[*] SDIO_CMD SDIO_CLK }]

# SDRAM
set_input_delay -clock { SDRAM_CLK } -max 6 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { SDRAM_CLK } -min 3 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { SDRAM_CLK } -max 2 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
set_output_delay -clock { SDRAM_CLK } -min 1.5 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
