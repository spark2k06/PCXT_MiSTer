derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
create_generated_clock -name SDRAM_CLK -source { FPGA_CLK2_50 }  [get_ports { SDRAM_CLK }]
set_input_delay -clock { SDRAM_CLK } -max 6.4 [get_ports { SDRAM_DQ[*] }]
set_input_delay -clock { SDRAM_CLK } -min 3.2 [get_ports { SDRAM_DQ[*] }]
set_output_delay -clock { SDRAM_CLK } -max 1.5 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
set_output_delay -clock { SDRAM_CLK } -min -0.8 [get_ports { SDRAM_DQ[*] SDRAM_DQM* SDRAM_A[*] SDRAM_n*  SDRAM_BA[*] SDRAM_CKE }]
