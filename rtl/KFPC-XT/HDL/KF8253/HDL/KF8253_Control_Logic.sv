//
// KF8253_Control_Logic
// Data Bus Buffer & Read/Write Control Logic
//

`include "KF8253_Definitions.svh"

module KF8253_Control_Logic (
    // Bus
    input   logic           clock,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,
    input   logic   [1:0]   address,
    input   logic   [7:0]   data_bus_in,

    // Control Signals
    output  logic   [7:0]   internal_data_bus,
    output  logic           write_control_0,
    output  logic           write_control_1,
    output  logic           write_control_2,
    output  logic           write_counter_0,
    output  logic           write_counter_1,
    output  logic           write_counter_2,
    output  logic           read_counter_0,
    output  logic           read_counter_1,
    output  logic           read_counter_2
);


    //
    // Internal Signals
    //
    logic           prev_write_enable_n;
    logic           write_flag;
    logic           write_control;
    logic   [2:0]   stable_address;
    logic           read_flag;


    //
    // Write Control
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            internal_data_bus <= 8'b00000000;
        else if (~write_enable_n & ~chip_select_n)
            internal_data_bus <= data_bus_in;
        else
            internal_data_bus <= internal_data_bus;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_write_enable_n <= 1'b1;
        else if (chip_select_n)
            prev_write_enable_n <= 1'b1;
        else
            prev_write_enable_n <= write_enable_n;
    end
    assign write_flag = ~prev_write_enable_n & write_enable_n;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            stable_address <= 2'b00;
        else
            stable_address <= address;
    end

    // Generate write request flags
    assign write_counter_0 = (stable_address == `ADDRESS_COUNTER_0)  & write_flag;
    assign write_counter_1 = (stable_address == `ADDRESS_COUNTER_1)  & write_flag;
    assign write_counter_2 = (stable_address == `ADDRESS_COUNTER_2)  & write_flag;
    assign write_control   = (stable_address == `ADDRESS_CONTROL)    & write_flag;
    assign write_control_0 = (internal_data_bus[7:6] == `SELECT_COUNTER_0) & write_control;
    assign write_control_1 = (internal_data_bus[7:6] == `SELECT_COUNTER_1) & write_control;
    assign write_control_2 = (internal_data_bus[7:6] == `SELECT_COUNTER_2) & write_control;


    //
    // Read Control
    //
    assign read_flag = ~read_enable_n  & ~chip_select_n;
    assign read_counter_0 = (address == `ADDRESS_COUNTER_0) & read_flag;
    assign read_counter_1 = (address == `ADDRESS_COUNTER_1) & read_flag;
    assign read_counter_2 = (address == `ADDRESS_COUNTER_2) & read_flag;

endmodule

