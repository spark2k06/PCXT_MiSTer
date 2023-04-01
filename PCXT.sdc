derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# Clocks
set CLOCK_CORE      {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set CLOCK_VGA_MDA   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}
set CLOCK_VGA_CGA   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[2].output_counter|divclk}
set CLOCK_UART      {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[3].output_counter|divclk}
set CLOCK_OPL       {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[4].output_counter|divclk}
set CLOCK_CHIP      {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[5].output_counter|divclk}
set CLOCK_VIDEO_MDA {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[6].output_counter|divclk}
set CLOCK_14_318    {emu|clk_14_318|q}
set CLOCK_4_77      {emu|clk_normal|clk_out|q}
set PCLK            {emu|peripheral_clock|q}

create_generated_clock -name clk_14_318 -source [get_pins $CLOCK_VGA_CGA] -divide_by 2 [get_pins $CLOCK_14_318]
create_generated_clock -name clk_4_77 -source [get_pins $CLOCK_14_318] -divide_by 3 -duty_cycle 33 [get_pins $CLOCK_4_77]
create_generated_clock -name peripheral_clock -source [get_pins $CLOCK_4_77] -divide_by 2 [get_pins $PCLK]
create_generated_clock -name SDRAM_CLK -source [get_pins $CLOCK_CHIP] [get_ports { SDRAM_CLK }]

# SPLASH
set_false_path -to [get_registers {emu:emu|splash_off}]

# UART
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks $CLOCK_UART]
set_false_path -from [get_clocks $CLOCK_UART] -to [get_clocks $CLOCK_CHIP]

# VIDEO
# NOTE: If the system clock and video clock are synchronous, the following description is not necessary.
set VIDEO_TO_SYSYEM_DELAY 10

set_false_path -to [get_registers  {emu:emu|scale_video_ff[*] \
                                    emu:emu|mda_mode_video_ff \
                                    emu:emu|screen_mode_video_ff[*] \
                                    emu:emu|border_video_ff \
                                    emu:emu|VIDEO_ARX[*] \
                                    emu:emu|VIDEO_ARY[*]}]

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_address[*]}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_address_1[*]   \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_address_1[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_data[*]}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_data_1[*]   \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_data_1[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_write_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_write_n_1   \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_write_n_1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_read_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_read_n_1   \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_read_n_1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_address_enable_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_address_enable_n_1   \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_address_enable_n_1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|MDA_CRTC_DOUT_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|MDA_CRTC_OE_1      \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|CGA_CRTC_DOUT_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|CGA_CRTC_OE_1}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|hps_io:hps_io|video_calc:video_calc|vid_hcnt[*]   \
                                    emu:emu|hps_io:hps_io|video_calc:video_calc|vid_nres[*]   \
                                    emu:emu|hps_io:hps_io|video_calc:video_calc|vid_vcnt[*]}] \
              -to   [get_registers {emu:emu|hps_io:hps_io|video_calc:video_calc|dout[*]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|mda_mode_video_ff}] \
              -to   [get_registers {emu:emu|hps_io:hps_io|io_dout[0]}] $VIDEO_TO_SYSYEM_DELAY

set_max_delay -from [get_registers {emu:emu|scale_video_ff[*]}] \
              -to   [get_registers {sl_r[*]                     \
                                    emu:emu|video_mixer:video_mixer_mda|CE_PIXEL}] $VIDEO_TO_SYSYEM_DELAY


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
                                    vmini[*]
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


# SDRAM
set_input_delay -clock { SDRAM_CLK } -max 6 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { SDRAM_CLK } -min 3 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { SDRAM_CLK } -max 2 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
set_output_delay -clock { SDRAM_CLK } -min 1.5 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]

