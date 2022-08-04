derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# Clocks
set CLOCK_CORE   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set CLOCK_CHIP   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[5].output_counter|divclk}
set CLOCK_UART   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[3].output_counter|divclk}
set CLOCK_14_318 {emu|clk_14_318|q}
set CLOCK_4_77   {emu|clk_normal|clk_out|q}
set PCLK         {emu|peripheral_clock|q}

create_generated_clock -name clk_14_318 -source [get_pins {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] -divide_by 2 [get_pins $CLOCK_14_318]
create_generated_clock -name clk_4_77 -source [get_pins $CLOCK_14_318] -divide_by 3 -duty_cycle 33 [get_pins $CLOCK_4_77]
create_generated_clock -name peripheral_clock -source [get_pins $CLOCK_4_77] -divide_by 2 [get_pins $PCLK]
create_generated_clock -name SDRAM_CLK -source [get_pins $CLOCK_CHIP] [get_ports { SDRAM_CLK }]

set_false_path -to [get_registers {emu:emu|clk_cpu_ff_1 emu:emu|pclk_ff_1 emu:emu|clk_opl2_ff_1}]

# status signal
set_false_path -from [get_registers {emu:emu|hps_io:hps_io|status[3] emu:emu|hps_io:hps_io|status[4] emu:emu|hps_io:hps_io|status[7]}]

# UART
set_false_path -from [get_clocks $CLOCK_CHIP] -to [get_clocks $CLOCK_UART]
set_false_path -from [get_clocks $CLOCK_UART] -to [get_clocks $CLOCK_CHIP]

# VIDEO
set_max_delay -from [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_address[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_data[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_write_n \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_io_read_n \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|video_address_enable_n}] \
              -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_address_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_data_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_write_n_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_io_read_n_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|mda_address_enable_n_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_address_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_data_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_write_n_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_io_read_n_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|cga_address_enable_n_1}] 10

set_max_delay -to   [get_registers {emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|MDA_CRTC_DOUT_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|MDA_CRTC_OE_1 \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|CGA_CRTC_DOUT_1[*] \
                                    emu:emu|CHIPSET:u_CHIPSET|PERIPHERALS:u_PERIPHERALS|CGA_CRTC_OE_1}] 10

# SDRAM
set_input_delay -clock { SDRAM_CLK } -max 6 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { SDRAM_CLK } -min 3 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { SDRAM_CLK } -max 2 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
set_output_delay -clock { SDRAM_CLK } -min 1.5 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]

