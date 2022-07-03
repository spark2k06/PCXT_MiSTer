derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# Clocks
set CLK_CORE   {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set CLK_14_318 {emu|clk_14_318|q}
set CLK_4_77   {emu|clk_normal|clk_out|q}
set PCLK       {emu|peripheral_clock|q}

create_generated_clock -name clk_14_318 -source [get_pins {emu|pll|pll_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] -divide_by 2 [get_pins $CLK_14_318]
create_generated_clock -name clk_4_77 -source [get_pins $CLK_14_318] -divide_by 3 -duty_cycle 33 [get_pins $CLK_4_77]
create_generated_clock -name peripheral_clock -source [get_pins $CLK_4_77] -divide_by 2 [get_pins $PCLK]
create_generated_clock -name SDRAM_CLK -source { FPGA_CLK2_50 }  [get_ports { SDRAM_CLK }]

# SDRAM
set_input_delay -clock { SDRAM_CLK } -max 6 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { SDRAM_CLK } -min 3 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { SDRAM_CLK } -max 2 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA SDRAM_CKE }]
set_output_delay -clock { SDRAM_CLK } -min 1.5 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA SDRAM_CKE }]
