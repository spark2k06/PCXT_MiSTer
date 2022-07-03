//
// KF8255_Group
// Group X Control
//
// Written by Kitune-san
//

`include "KF8255_Definitions.svh"

module KF8255_Group (
    // Bus
    input   logic           clock,
    input   logic           reset,

    input   logic   [3:0]   internal_data_bus,
    input   logic           write_register,

    // Control Data Registers
    output  logic           update_group_mode,
    output  logic   [1:0]   mode_select_reg,
    output  logic           port_1_io_reg,
    output  logic           port_2_io_reg
);

    //
    // Generate update mode flag
    //
    assign update_group_mode = ({mode_select_reg[1:0], port_1_io_reg} != internal_data_bus[3:1]) & write_register;


    //
    // Set mode select register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            mode_select_reg <= `KF8255_CONTROL_MODE_0;
        else if (write_register)
            mode_select_reg <= internal_data_bus[3:2];
        else
            mode_select_reg <= mode_select_reg;
    end


    //
    // Set port I/O registers
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_1_io_reg <= `PORT_INPUT;
        else if (write_register)
            port_1_io_reg <= internal_data_bus[1];
        else
            port_1_io_reg <= port_1_io_reg;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_2_io_reg <= `PORT_INPUT;
        else if (write_register)
            port_2_io_reg <= internal_data_bus[0];
        else
            port_2_io_reg <= port_2_io_reg;
    end

endmodule
