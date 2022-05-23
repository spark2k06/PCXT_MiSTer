
`ifndef KF8253_DEFINITIONS_SVH
`define KF8253_DEFINITIONS_SVH

`define ADDRESS_COUNTER_0       (2'b00)
`define ADDRESS_COUNTER_1       (2'b01)
`define ADDRESS_COUNTER_2       (2'b10)
`define ADDRESS_CONTROL         (2'b11)

`define SELECT_COUNTER_0        (2'b00)
`define SELECT_COUNTER_1        (2'b01)
`define SELECT_COUNTER_2        (2'b10)

`define RL_COUNTER_LATCH        (2'b00)
`define RL_SELECT_MSB           (2'b10)
`define RL_SELECT_LSB           (2'b01)
`define RL_SELECT_LSB_MSB       (2'b11)

`define KF8253_CONTROL_MODE_0   (3'b000)
`define KF8253_CONTROL_MODE_1   (3'b001)
`define KF8253_CONTROL_MODE_2   (3'b?10)
`define KF8253_CONTROL_MODE_3   (3'b?11)
`define KF8253_CONTROL_MODE_4   (3'b100)
`define KF8253_CONTROL_MODE_5   (3'b101)

`endif
