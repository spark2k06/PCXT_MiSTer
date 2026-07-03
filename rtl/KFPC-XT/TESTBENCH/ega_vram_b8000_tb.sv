`timescale 1ns / 1ps

module ega_vram_b8000_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg         clk = 1'b0;
    reg         clk_vram = 1'b0;
    reg  [15:0] cpu_addr = 16'h0000;
    reg         cpu_a16 = 1'b0;
    reg  [7:0]  cpu_data_in = 8'h00;
    wire [7:0]  cpu_data_out;
    reg         cpu_we = 1'b0;
    reg         cpu_re = 1'b0;
    reg         cpu_mem_select = 1'b0;
    reg  [3:0]  plane_write_mask = 4'hF;
    reg         odd_even_mode = 1'b0;
    reg         chain2_write = 1'b0;
    reg         chain2_read = 1'b0;
    reg         extended_memory = 1'b1;
    reg  [1:0]  mem_map_sel = 2'b11;
    reg         page_select = 1'b0;
    reg  [1:0]  write_mode = 2'b00;
    reg  [1:0]  read_mode = 2'b00;
    reg  [1:0]  read_plane_sel = 2'b00;
    reg  [7:0]  color_compare = 8'h00;
    reg  [7:0]  color_dont_care = 8'h0F;
    reg  [7:0]  bit_mask = 8'hFF;
    reg  [7:0]  set_reset = 8'h00;
    reg  [3:0]  enable_set_reset = 4'h0;
    reg  [1:0]  rop_select = 2'b00;
    reg  [2:0]  rotate_count = 3'b000;
    reg  [15:0] crt_addr = 16'h0000;
    reg         crt_re = 1'b0;
    reg  [15:0] text_cell_addr = 16'h0000;
    reg  [15:0] text_font_addr = 16'h0000;
    reg         text_re = 1'b0;
    reg         splash_text_we = 1'b0;
    reg  [10:0] splash_text_addr = 11'h000;
    reg         splash_text_attr = 1'b0;
    reg  [7:0]  splash_text_data = 8'h00;
    wire [7:0]  crt_plane0;
    wire [7:0]  crt_plane1;
    wire [7:0]  crt_plane2;
    wire [7:0]  crt_plane3;

    integer failures = 0;

    ega_vram dut (
        .clk(clk),
        .clk_vram(clk_vram),
        .cpu_addr(cpu_addr),
        .cpu_a16(cpu_a16),
        .cpu_data_in(cpu_data_in),
        .cpu_data_out(cpu_data_out),
        .cpu_we(cpu_we),
        .cpu_re(cpu_re),
        .cpu_mem_select(cpu_mem_select),
        .plane_write_mask(plane_write_mask),
        .odd_even_mode(odd_even_mode),
        .chain2_write(chain2_write),
        .chain2_read(chain2_read),
        .extended_memory(extended_memory),
        .mem_map_sel(mem_map_sel),
        .page_select(page_select),
        .write_mode(write_mode),
        .read_mode(read_mode),
        .read_plane_sel(read_plane_sel),
        .color_compare(color_compare),
        .color_dont_care(color_dont_care),
        .bit_mask(bit_mask),
        .set_reset(set_reset),
        .enable_set_reset(enable_set_reset),
        .rop_select(rop_select),
        .rotate_count(rotate_count),
        .crt_addr(crt_addr),
        .crt_re(crt_re),
        .text_cell_addr(text_cell_addr),
        .text_font_addr(text_font_addr),
        .text_re(text_re),
        .splash_text_we(splash_text_we),
        .splash_text_addr(splash_text_addr),
        .splash_text_attr(splash_text_attr),
        .splash_text_data(splash_text_data),
        .crt_plane0(crt_plane0),
        .crt_plane1(crt_plane1),
        .crt_plane2(crt_plane2),
        .crt_plane3(crt_plane3),
        .latch_plane0(),
        .latch_plane1(),
        .latch_plane2(),
        .latch_plane3(),
        .debug_old_plane0(),
        .debug_old_plane1(),
        .debug_old_plane2(),
        .debug_old_plane3(),
        .debug_new_plane0(),
        .debug_new_plane1(),
        .debug_new_plane2(),
        .debug_new_plane3()
    );

    always #5 clk = ~clk;
    always #7 clk_vram = ~clk_vram;

    function automatic [16:0] ega_abs_to_offset(input [19:0] abs_addr);
        begin
            ega_abs_to_offset = (abs_addr - 20'hA0000) & 17'h1FFFF;
        end
    endfunction

    function automatic [15:0] b8000_plane_addr(input [19:0] abs_addr);
        reg [16:0] offset;
        begin
            offset = ega_abs_to_offset(abs_addr);
            b8000_plane_addr = offset[15:0] & 16'h7FFF;
        end
    endfunction

    function automatic expected_b8000_select(input [19:0] abs_addr);
        begin
            expected_b8000_select = (abs_addr >= 20'hB8000) && (abs_addr <= 20'hBFFFF);
        end
    endfunction

    task automatic expect8(input [8*48-1:0] label, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                failures = failures + 1;
                $display("FAIL %0s expected=%02h actual=%02h", label, expected, actual);
            end
        end
    endtask

    task automatic cpu_write_abs(input [19:0] abs_addr, input [7:0] data);
        reg [16:0] offset;
        begin
            offset = ega_abs_to_offset(abs_addr);
            @(negedge clk);
            cpu_addr = offset[15:0];
            cpu_a16 = offset[16];
            cpu_data_in = data;
            cpu_re = 1'b0;
            cpu_we = 1'b1;
            cpu_mem_select = expected_b8000_select(abs_addr);
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            cpu_we = 1'b0;
            cpu_mem_select = 1'b0;
        end
    endtask

    task automatic cpu_read_abs(input [19:0] abs_addr);
        reg [16:0] offset;
        begin
            offset = ega_abs_to_offset(abs_addr);
            @(negedge clk);
            cpu_addr = offset[15:0];
            cpu_a16 = offset[16];
            cpu_re = 1'b1;
            cpu_we = 1'b0;
            cpu_mem_select = expected_b8000_select(abs_addr);
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            cpu_re = 1'b0;
            cpu_mem_select = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);

        $display("TEST: B8000 memory map selects EGA VRAM");
        dut.plane0[b8000_plane_addr(20'hB8000)] = 8'h00;
        dut.plane0[b8000_plane_addr(20'hBFFFF)] = 8'h00;
        cpu_write_abs(20'hB8000, 8'h41);
        cpu_write_abs(20'hBFFFF, 8'h5A);
        cpu_write_abs(20'hB7FFF, 8'hEE);
        expect8("B8000 first byte writes plane0", dut.plane0[b8000_plane_addr(20'hB8000)], 8'h41);
        expect8("BFFFF last byte writes plane0", dut.plane0[b8000_plane_addr(20'hBFFFF)], 8'h5A);

        read_plane_sel = 2'b00;
        cpu_read_abs(20'hB8000);
        expect8("B8000 read returns plane0", cpu_data_out, 8'h41);
        cpu_read_abs(20'hBFFFF);
        expect8("BFFFF read returns plane0", cpu_data_out, 8'h5A);

        $display("TEST: B8000 odd/even page remap stays inside EGA VRAM");
        odd_even_mode = 1'b1;
        plane_write_mask = 4'h1;
        page_select = 1'b1;
        cpu_write_abs(20'hB8002, 8'h66);
        expect8("page_select=1 forces even EGA address", dut.plane0[16'h0002], 8'h66);
        page_select = 1'b0;
        cpu_write_abs(20'hB8002, 8'h77);
        expect8("page_select=0 forces odd EGA address", dut.plane0[16'h0003], 8'h77);

        if (failures == 0)
            $display("PASS ega_vram_b8000_tb");
        else
            $display("FAIL ega_vram_b8000_tb failures=%0d", failures);

        $finish(failures == 0 ? 0 : 1);
    end

endmodule
