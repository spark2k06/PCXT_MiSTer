//
// KF8255_port
// Group X Port Y
//
// Written by Kitune-san
//

`include "KF8255_Definitions.svh"

module KF8255_Port (
    // Bus
    input   logic           clock,
    input   logic           reset,

    input   logic   [7:0]   internal_data_bus,
    input   logic           write_port,
    input   logic           update_mode,

    // Control Data Registers
    input   logic   [1:0]   mode_select_reg,
    input   logic           port_io_reg,

    // Signals
    input   logic           strobe,
    input   logic           hiz,

    // Ports
    output  logic           port_io,
    output  logic   [7:0]   port_out,
    input   logic   [7:0]   port_in,
    output  logic   [7:0]   read
);


    //
    // Select Input(Hi-Z) or Output
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_io <= `PORT_INPUT;
        else
            casez (mode_select_reg)
                `KF8255_CONTROL_MODE_0: port_io <= port_io_reg;
                `KF8255_CONTROL_MODE_1: port_io <= port_io_reg;
                `KF8255_CONTROL_MODE_2: port_io <= (hiz == 1'b0) ? `PORT_OUTPUT
                                                                 : `PORT_INPUT;
                default:         port_io <= port_io_reg;
            endcase
    end


    //
    // Output
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_out <= 8'b00000000;
        else if (update_mode)
            port_out <= 8'b00000000;
        else if (write_port)
            port_out <= internal_data_bus;
        else
            port_out <= port_out;
    end


    //
    // Input
    //
    logic   [7:0]   read_tmp;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_tmp <= 8'b00000000;
        else if (update_mode)
            read_tmp <= 8'b00000000;
        else
            casez (mode_select_reg)
                `KF8255_CONTROL_MODE_0: read_tmp <= port_in;
                `KF8255_CONTROL_MODE_1: read_tmp <= (strobe == 1'b0) ? read_tmp
                                                                     : port_in;
                `KF8255_CONTROL_MODE_2: read_tmp <= (strobe == 1'b0) ? read_tmp
                                                                     : port_in;
                default:         read_tmp <= read_tmp;
            endcase
    end

    //
    // Read data
    //
    assign read = (port_io == `PORT_INPUT) ? read_tmp : port_out;

endmodule

