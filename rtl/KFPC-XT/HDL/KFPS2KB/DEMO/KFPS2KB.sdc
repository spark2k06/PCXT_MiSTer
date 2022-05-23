create_clock -name CLK -period 20.000 [get_ports {CLK}]
create_clock -name CLK_5MHZ -period 200.000
derive_pll_clocks
derive_clock_uncertainty
set_input_delay -clock {CLK_5MHZ} -max 10 [all_inputs]
set_input_delay -clock {CLK_5MHZ} -min 5 [all_inputs]
set_output_delay -clock {CLK_5MHZ} -max 10 [all_outputs]
set_output_delay -clock {CLK_5MHZ} -min 5 [all_outputs]
