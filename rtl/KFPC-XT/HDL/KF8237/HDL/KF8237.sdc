create_clock -name CLK -period 200.000 [get_ports {clock}]
derive_clock_uncertainty
set_input_delay -clock {CLK} -max 10 [all_inputs]
set_input_delay -clock {CLK} -min 5 [all_inputs]
set_output_delay -clock {CLK} -max 10 [all_outputs]
set_output_delay -clock {CLK} -min 5 [all_outputs]
