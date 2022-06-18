derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
set_input_delay -clock { FPGA_CLK2_50 } -max 6 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { FPGA_CLK2_50 } -min 3 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { FPGA_CLK2_50 } -max 2 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA SDRAM_CLK }]
set_output_delay -clock { FPGA_CLK2_50 } -min 0 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA SDRAM_CLK }]
