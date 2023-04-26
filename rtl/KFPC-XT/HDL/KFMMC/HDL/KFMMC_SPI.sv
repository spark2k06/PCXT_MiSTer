//
// KFMMC_SPI
// Access to MMC using SPI
//
// Written by kitune-san
//
module KFMMC_SPI (
    input   logic           clock,
    input   logic           reset,

    input   logic   [7:0]   send_data,
    output  logic   [7:0]   recv_data,

    input   logic           start_communication,
    output  logic           busy_flag,

    input   logic   [7:0]   spi_clock_cycle,
    output  logic           spi_clk,
    output  logic           spi_mosi,
    input   logic           spi_miso
);
    //
    // Internal signals
    //
    logic   [7:0]   clk_cycle_counter;
    logic           edge_spi_clk;
    logic           sample_edge;
    logic           shift_edge;
    logic   [7:0]   txd_register;
    logic   [8:0]   rxd_register;
    logic   [3:0]   bit_count;
    logic           access_flag;


    //
    // SPI CLK
    //
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            clk_cycle_counter <= 8'd01;
        else if (access_flag)
            if (edge_spi_clk)
                clk_cycle_counter <= 8'd01;
            else
                clk_cycle_counter <= clk_cycle_counter + 1'd01;
        else
            clk_cycle_counter <= 8'd01;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            spi_clk <= 1'b0;
        else if ((access_flag) && (bit_count != 4'd1))
            if (edge_spi_clk)
                spi_clk <= ~spi_clk;
            else
                spi_clk <=  spi_clk;
        else
            spi_clk <= 1'b0;
    end

    assign edge_spi_clk = (clk_cycle_counter == {1'b0, spi_clock_cycle[7:1]});
    assign sample_edge  = (edge_spi_clk) & (spi_clk == 1'b0); // 0 -> 1
    assign shift_edge   = (edge_spi_clk) & (spi_clk == 1'b1); // 1 -> 0


    //
    // SPI MOSI
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            txd_register <= 8'h00;
        else if (access_flag)
            if (shift_edge)
                txd_register <= {txd_register[6:0], 1'b1};
            else
                txd_register <= txd_register;
        else if (start_communication)
            txd_register <= send_data;
        else
            txd_register <= 8'h00;
    end

    always_comb begin
        if (access_flag)
            spi_mosi = txd_register[7];
        else
            spi_mosi = 1'b1;
    end


    //
    // SPI MISO
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            rxd_register <= 9'h000;
        else if (access_flag)
            if (sample_edge)
                rxd_register <= {rxd_register[8:1], spi_miso};
            else if (shift_edge)
                rxd_register <= {rxd_register[7:0], 1'b0};
            else
                rxd_register <= rxd_register;
        else
            rxd_register <= rxd_register;
    end

    assign recv_data = rxd_register[8:1];


    //
    // Bit count
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            bit_count <= 4'd0;
        else if (access_flag)
            if (shift_edge)
                bit_count <= bit_count - 4'd1;
            else if ((sample_edge) && (bit_count == 4'd1))
                bit_count <= 4'd0;
            else
                bit_count <= bit_count;
        else if (start_communication)
            bit_count <= 4'd9;
    end

    assign access_flag = (bit_count != 4'd0);
    assign busy_flag   = (reset) ? 1'b1 : access_flag;

endmodule

