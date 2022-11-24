//
// XT2IDE written by kitune-san
//
module XT2IDE
(
    input   logic           clock,
    input   logic           reset,

    input   logic           high_speed,

    input   logic           chip_select_n,
    input   logic           io_read_n,
    input   logic           io_write_n,

    input   logic   [4:0]   address,
    input   logic   [7:0]   data_bus_in,
    output  logic   [7:0]   data_bus_out,

    output  logic           ide_cs1fx,
    output  logic           ide_cs3fx,
    output  logic           ide_io_read_n,
    output  logic           ide_io_write_n,

    output  logic   [2:0]   ide_address,
    input   logic   [15:0]  ide_data_bus_in,
    output  logic   [15:0]  ide_data_bus_out
);

    logic           select_1;
    logic           select_2;
    logic           latch_high_read_byte;
    logic           read_high_byte;
    logic           latch_high_write_byte;
    logic   [7:0]   read_buffer;

    //
    // Control Signals
    //
    assign select_1 = high_speed ? address[0] : address[3];
    assign select_2 = high_speed ? address[3] : address[0];

    always_comb
    begin
        latch_high_read_byte    = 1'b0;
        read_high_byte          = 1'b0;
        latch_high_write_byte   = 1'b0;

        if (~address[2] & ~address[1] & ~select_2 & ~chip_select_n) begin
            casez ({select_1, io_read_n, io_write_n})
                3'b001: latch_high_read_byte    = 1'b1;
                3'b101: read_high_byte          = 1'b1;
                3'b110: latch_high_write_byte   = 1'b1;
            endcase
        end
    end

    assign  ide_io_read_n   = io_read_n;
    assign  ide_io_write_n  = io_write_n;
    assign  ide_cs1fx       =  select_1 | chip_select_n;
    assign  ide_cs3fx       = ~select_1 | chip_select_n;

    //
    // XT Address -> IDE Address
    //
    assign  ide_address = {address[2:1], select_2};

    //
    // XT Data Bus -> IDE Data Bus
    //
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            ide_data_bus_out[15:8]  <= 8'hFF;
        else if (~chip_select_n & latch_high_write_byte)
            ide_data_bus_out[15:8]  <= data_bus_in;
        else
            ide_data_bus_out[15:8]  <= ide_data_bus_out[15:8];
    end

    always_comb
    begin
        if (io_write_n | chip_select_n)
            ide_data_bus_out[7:0]   = 8'hFF;
        else
            ide_data_bus_out[7:0]   = data_bus_in;
    end

    //
    // IDE Data Bus -> XT Data Bus
    //
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            read_buffer <= 8'hFF;
        else if (~ide_io_read_n & latch_high_read_byte)
            read_buffer <= ide_data_bus_in[15:8];
        else
            read_buffer <= read_buffer;
    end

    always_comb
    begin
        if (read_high_byte)
            data_bus_out    = read_buffer;
        else if (~io_read_n & ~chip_select_n)
            data_bus_out    = ide_data_bus_in[7:0];
        else
            data_bus_out    = 8'hFF;
    end

endmodule
