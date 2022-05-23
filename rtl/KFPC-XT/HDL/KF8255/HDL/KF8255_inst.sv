//
// Install KF8255 (Example)
//

module TOP (
    input   logic           clock,
    input   logic           reset_in,

    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,

    input   logic   [1:0]   address,
    inout   logic   [7:0]   data_bus,

    inout   logic   [7:0]   port_a,
    inout   logic   [7:0]   port_b,
    inout   logic   [7:0]   port_c
);


    //
    // Internal signals
    //
    logic           res_ff;
    logic           reset;

    logic   [7:0]   data_bus_in;
    logic   [7:0]   data_bus_out;

    logic   [7:0]   port_a_in_ff;
    logic   [7:0]   port_a_in;
    logic   [7:0]   port_a_out;
    logic           port_a_io;

    logic   [7:0]   port_b_in_ff;
    logic   [7:0]   port_b_in;
    logic   [7:0]   port_b_out;
    logic           port_b_io;

    logic   [7:0]   port_c_in_ff;
    logic   [7:0]   port_c_in;
    logic   [7:0]   port_c_out;
    logic   [7:0]   port_c_io;

    //
    // RESET
    //
    always_ff @(negedge clock, posedge reset_in) begin
        if (reset_in) begin
            res_ff <= 1'b1;
            reset  <= 1'b1;
        end
        else begin
            res_ff <= 1'b0;
            reset  <= res_ff;
        end
    end


    //
    // Data bus
    //
    assign data_bus = (~chip_select_n & ~read_enable_n & write_enable_n) ? data_bus_out : 8'bzzzzzzzz;
    assign data_bus_in = data_bus;


    //
    // Ports
    //
    assign port_a    = (~port_a_io)    ? port_a_out    : 8'bzzzzzzzz;
    assign port_b    = (~port_b_io)    ? port_b_out    : 8'bzzzzzzzz;
    assign port_c[0] = (~port_c_io[0]) ? port_c_out[0] : 1'bz;
    assign port_c[1] = (~port_c_io[1]) ? port_c_out[1] : 1'bz;
    assign port_c[2] = (~port_c_io[2]) ? port_c_out[2] : 1'bz;
    assign port_c[3] = (~port_c_io[3]) ? port_c_out[3] : 1'bz;
    assign port_c[4] = (~port_c_io[4]) ? port_c_out[4] : 1'bz;
    assign port_c[5] = (~port_c_io[5]) ? port_c_out[5] : 1'bz;
    assign port_c[6] = (~port_c_io[6]) ? port_c_out[6] : 1'bz;
    assign port_c[7] = (~port_c_io[7]) ? port_c_out[7] : 1'bz;

    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            port_a_in_ff <= 8'b00000000;
            port_a_in    <= 8'b00000000;
        end
        else begin
            port_a_in_ff <= port_a;
            port_a_in    <= port_a_in_ff;
        end
    end

    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            port_b_in_ff <= 8'b00000000;
            port_b_in    <= 8'b00000000;
        end
        else begin
            port_b_in_ff <= port_b;
            port_b_in    <= port_b_in_ff;
        end
    end

    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            port_c_in_ff <= 8'b00000000;
            port_c_in    <= 8'b00000000;
        end
        else begin
            port_c_in_ff <= port_c;
            port_c_in    <= port_c_in_ff;
        end
    end


    //
    // Install KF8255
    //
    KF8255 u_KF8255 (.*);

endmodule

