//
// KF8255_Control_Logic
// Data Bus Buffer & Read/Write Control Logic
//
// Written by Kitune-san
//

`include "KF8255_Definitions.svh"

module KF8255_Control_Logic (
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
    output  logic           write_port_a,
    output  logic           write_port_b,
    output  logic           write_port_c,
    output  logic           write_control,
    output  logic           read_port_a,
    output  logic           read_port_b,
    output  logic           read_port_c
);


    //
    // Internal Signals
    //
    logic           prev_write_enable_n;
    logic           write_flag;
    logic   [2:0]   stable_address;


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
    assign write_port_a  = (stable_address == `ADDRESS_PORT_A)  & write_flag;
    assign write_port_b  = (stable_address == `ADDRESS_PORT_B)  & write_flag;
    assign write_port_c  = (stable_address == `ADDRESS_PORT_C)  & write_flag;
    assign write_control = (stable_address == `ADDRESS_CONTROL) & write_flag;


    //
    // Read Control
    //
    always_comb begin
        read_port_a = 1'b0;
        read_port_b = 1'b0;
        read_port_c = 1'b0;

        if (~read_enable_n  & ~chip_select_n) begin
            // Generate read request flags
            case (address)
                `ADDRESS_PORT_A : read_port_a = 1'b1;
                `ADDRESS_PORT_B : read_port_b = 1'b1;
                `ADDRESS_PORT_C : read_port_c = 1'b1;
                default         : read_port_a = 1'b1;
            endcase
        end
    end
endmodule

