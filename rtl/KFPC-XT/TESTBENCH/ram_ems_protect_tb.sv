// Regression for the write protection of the EMS page that sits at EC000.
//
// "BIOS Writable" protects the EC00 ROM, not RAM: when the fourth page of an
// E000 EMS frame is mapped at EC000 it has to be writable even while the
// protection is on, which is its default. F000 stays protected.
`timescale 1ns / 1ps

module ram_ems_protect_tb;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #10 clock = ~clock; // 50 MHz, matching clk_chipset

    logic [1:0]  clk_select = 2'b11;
    logic [19:0] address = 20'h00000;
    logic        ems_b4 = 1'b0;
    logic [1:0]  bios_protect_flag = 2'b11;
    logic [7:0]  data_in = 8'h00;
    logic        memory_read_n = 1'b1;
    logic        memory_write_n = 1'b1;
    logic        no_command_state = 1'b1;

    wire [7:0]  data_out;
    wire        memory_access_ready;
    wire        ram_address_select_n;
    wire        initilized_sdram;
    wire [12:0] sdram_address;
    wire        sdram_cke;
    wire        sdram_cs;
    wire        sdram_ras;
    wire        sdram_cas;
    wire        sdram_we;
    wire [1:0]  sdram_ba;
    wire [15:0] sdram_dq_out;
    wire        sdram_dq_io;
    wire        sdram_ldqm;
    wire        sdram_udqm;

    logic [6:0] map_ems [0:3];

    RAM dut (
        .clock                 (clock),
        .reset                 (reset),
        .enable_sdram          (1'b1),
        .initilized_sdram      (initilized_sdram),
        .address               (address),
        .internal_data_bus     (data_in),
        .data_bus_out          (data_out),
        .word_read_request     (1'b0),
        .word_write_request    (1'b0),
        .data_bus_in_word      (16'h0000),
        .data_bus_out_word     (),
        .memory_read_n         (memory_read_n),
        .memory_write_n        (memory_write_n),
        .no_command_state      (no_command_state),
        .memory_access_ready   (memory_access_ready),
        .ram_address_select_n  (ram_address_select_n),
        .sdram_address         (sdram_address),
        .sdram_cke             (sdram_cke),
        .sdram_cs              (sdram_cs),
        .sdram_ras             (sdram_ras),
        .sdram_cas             (sdram_cas),
        .sdram_we              (sdram_we),
        .sdram_ba              (sdram_ba),
        .sdram_dq_in           (16'h0000),
        .sdram_dq_out          (sdram_dq_out),
        .sdram_dq_io           (sdram_dq_io),
        .sdram_ldqm            (sdram_ldqm),
        .sdram_udqm            (sdram_udqm),
        .map_ems               (map_ems),
        .ems_b1                (1'b0),
        .ems_b2                (1'b0),
        .ems_b3                (1'b0),
        .ems_b4                (ems_b4),
        .tandy_bios_flag       (1'b0),
        .enable_a000h          (1'b1),
        .bios_protect_flag     (bios_protect_flag),
        .wait_count_clk_en     (1'b1),
        .clk_select            (clk_select),
        .ram_read_wait_cycle   (2'd0),
        .ram_write_wait_cycle  (2'd0)
    );

    integer errors = 0;

    task automatic check(input string what, input logic [19:0] a, input logic b4,
                         input logic [1:0] flag, input logic expect_protect);
        address = a; ems_b4 = b4; bios_protect_flag = flag;
        #1;
        if (dut.write_protect !== expect_protect) begin
            errors++;
            $display("ERROR: %s: write_protect=%b, expected %b", what, dut.write_protect, expect_protect);
        end
    endtask

    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
        check("EC00 ROM, protection on",            20'hEC000, 1'b0, 2'b11, 1'b1);
        check("EC00 ROM, last byte, protection on", 20'hEFFFF, 1'b0, 2'b01, 1'b1);
        check("EC00 ROM, protection off",           20'hEC000, 1'b0, 2'b10, 1'b0);
        check("EMS page 4 at EC000, protection on", 20'hEC000, 1'b1, 2'b11, 1'b0);
        check("EMS page 4 at EFFFF, protection on", 20'hEFFFF, 1'b1, 2'b01, 1'b0);
        check("F000 main ROM, protection on",       20'hF0000, 1'b0, 2'b10, 1'b1);
        check("F000 main ROM, flag for EC00 only",  20'hF0000, 1'b0, 2'b01, 1'b0);
        check("below EC000, protection on",         20'hE8000, 1'b0, 2'b11, 1'b0);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
