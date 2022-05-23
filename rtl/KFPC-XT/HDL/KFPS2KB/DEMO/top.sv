//
// On-board Check Code
//
// Written by kitune-san
//
`define POR_MAX 16'hffff

module TOP (
    input   logic           CLK,
    input   logic           PS2_CLK,
    input   logic           PS2_DAT,

    output  logic   [6:0]   HEX0,
    output  logic   [6:0]   HEX1,
    output  logic   [6:0]   HEX2,
    output  logic   [6:0]   HEX3,
    output  logic   [6:0]   HEX4,
    output  logic   [6:0]   HEX5
);

    logic   clock;
    logic   reset;

    //
    // PLL
    //
    PLL PLL (
        .refclk     (CLK),
        .rst        (1'b0),
        .outclk_0   (clock)
    );

    //
    // Power On Reset
    //
    logic   [15:0]  por_count;

    always_ff @(negedge CLK)
    begin
        if (por_count != `POR_MAX) begin
            reset <= 1'b1;
            por_count <= por_count + 16'h0001;
        end
        else begin
            reset <= 1'b0;
            por_count <= por_count;
        end
    end


    //
    // Input F/F PS2_CLK
    //
    logic   device_clock_ff;
    logic   device_clock;

    always_ff @(negedge clock, posedge reset)
    begin
        if (reset) begin
            device_clock_ff <= 1'b0;
            device_clock    <= 1'b0;
        end
        else begin
            device_clock_ff <= PS2_CLK;
            device_clock    <= device_clock_ff ;
        end
    end


    //
    // Input F/F PS2_DAT
    //
    logic   device_data_ff;
    logic   device_data;

    always_ff @(negedge clock, posedge reset)
    begin
        if (reset) begin
            device_data_ff <= 1'b0;
            device_data    <= 1'b0;
        end
        else begin
            device_data_ff <= PS2_DAT;
            device_data    <= device_data_ff;
        end
    end


    //
    // Install KFPS2KB
    //
    logic           irq;
    logic   [7:0]   keycode;
    logic           clear_keycode;

    KFPS2KB u_KFPS2KB (.*);


    //
    // Input Data
    //
    logic   [7:0]   keycode_0;
    logic   [7:0]   keycode_1;
    logic   [7:0]   keycode_2;

    always_ff @(negedge clock, posedge reset)
    begin
        if (reset) begin
            keycode_0 <= 8'h00;
            keycode_1 <= 8'h00;
            keycode_2 <= 8'h00;
            clear_keycode <= 1'b0;
        end
        else if (irq) begin
            if (clear_keycode == 1'b0) begin
                keycode_0 <= keycode;
                keycode_1 <= keycode_0;
                keycode_2 <= keycode_1;
            end
            else begin
                keycode_0 <= keycode_0;
                keycode_1 <= keycode_1;
                keycode_2 <= keycode_2;
            end
            clear_keycode <= 1'b1;
        end
        else begin
            keycode_0 <= keycode_0;
            keycode_1 <= keycode_1;
            keycode_2 <= keycode_2;
            clear_keycode <= 1'b0;
        end
    end


    //
    // Display
    //
    function [6:0] CONV7SEG (input logic [3:0] data);
    begin
        case (data)
            4'h0:    CONV7SEG = 7'b1000000;
            4'h1:    CONV7SEG = 7'b1111001;
            4'h2:    CONV7SEG = 7'b0100100;
            4'h3:    CONV7SEG = 7'b0110000;
            4'h4:    CONV7SEG = 7'b0011001;
            4'h5:    CONV7SEG = 7'b0010010;
            4'h6:    CONV7SEG = 7'b0000010;
            4'h7:    CONV7SEG = 7'b1011000;
            4'h8:    CONV7SEG = 7'b0000000;
            4'h9:    CONV7SEG = 7'b0010000;
            4'ha:    CONV7SEG = 7'b0001000;
            4'hb:    CONV7SEG = 7'b0000011;
            4'hc:    CONV7SEG = 7'b1000110;
            4'hd:    CONV7SEG = 7'b0100001;
            4'he:    CONV7SEG = 7'b0000110;
            4'hf:    CONV7SEG = 7'b0001110;
            default: CONV7SEG = 7'b1111111;
        endcase
    end
    endfunction

    assign HEX0 = CONV7SEG(keycode_0[3:0]);
    assign HEX1 = CONV7SEG(keycode_0[7:4]);
    assign HEX2 = CONV7SEG(keycode_1[3:0]);
    assign HEX3 = CONV7SEG(keycode_1[7:4]);
    assign HEX4 = CONV7SEG(keycode_2[3:0]);
    assign HEX5 = CONV7SEG(keycode_2[7:4]);

endmodule
