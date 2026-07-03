`timescale 1ns / 1ps

module ega_vram_tb;

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
    reg  [3:0]  plane_write_mask = 4'h0;
    reg         odd_even_mode = 1'b0;
    reg         chain2_write = 1'b0;
    reg         chain2_read = 1'b0;
    reg         extended_memory = 1'b0;
    reg  [1:0]  mem_map_sel = 2'b00;
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
    wire [7:0]  latch_plane0;
    wire [7:0]  latch_plane1;
    wire [7:0]  latch_plane2;
    wire [7:0]  latch_plane3;
    wire [7:0]  debug_old_plane0;
    wire [7:0]  debug_old_plane1;
    wire [7:0]  debug_old_plane2;
    wire [7:0]  debug_old_plane3;
    wire [7:0]  debug_new_plane0;
    wire [7:0]  debug_new_plane1;
    wire [7:0]  debug_new_plane2;
    wire [7:0]  debug_new_plane3;

    integer failures = 0;
    reg [8*64-1:0] current_test = "initialization";

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
        .latch_plane0(latch_plane0),
        .latch_plane1(latch_plane1),
        .latch_plane2(latch_plane2),
        .latch_plane3(latch_plane3),
        .debug_old_plane0(debug_old_plane0),
        .debug_old_plane1(debug_old_plane1),
        .debug_old_plane2(debug_old_plane2),
        .debug_old_plane3(debug_old_plane3),
        .debug_new_plane0(debug_new_plane0),
        .debug_new_plane1(debug_new_plane1),
        .debug_new_plane2(debug_new_plane2),
        .debug_new_plane3(debug_new_plane3)
    );

    always #5 clk = ~clk;
    always #7 clk_vram = ~clk_vram;

    function automatic [7:0] rotate_right8(
        input [7:0] value,
        input [2:0] count
    );
        begin
            case (count)
                3'd0: rotate_right8 = value;
                3'd1: rotate_right8 = {value[0], value[7:1]};
                3'd2: rotate_right8 = {value[1:0], value[7:2]};
                3'd3: rotate_right8 = {value[2:0], value[7:3]};
                3'd4: rotate_right8 = {value[3:0], value[7:4]};
                3'd5: rotate_right8 = {value[4:0], value[7:5]};
                3'd6: rotate_right8 = {value[5:0], value[7:6]};
                default: rotate_right8 = {value[6:0], value[7]};
            endcase
        end
    endfunction

    function automatic [7:0] apply_rop(
        input [7:0] old_byte,
        input [7:0] src_byte,
        input [1:0] rop
    );
        begin
            case (rop)
                2'b01: apply_rop = old_byte & src_byte;
                2'b10: apply_rop = old_byte | src_byte;
                2'b11: apply_rop = old_byte ^ src_byte;
                default: apply_rop = src_byte;
            endcase
        end
    endfunction

    function automatic [7:0] expected_mode0_byte(
        input [7:0] old_byte,
        input [7:0] host_byte,
        input       plane_set_reset,
        input       plane_enable_set_reset,
        input [7:0] mask_byte,
        input [1:0] rop,
        input [2:0] rotate_count_sel
    );
        reg [7:0] rotated_host_byte;
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            rotated_host_byte = rotate_right8(host_byte, rotate_count_sel);
            src_byte = plane_enable_set_reset ? {8{plane_set_reset}} : rotated_host_byte;
            alu_byte = apply_rop(old_byte, src_byte, rop);
            expected_mode0_byte = (alu_byte & mask_byte) | (old_byte & ~mask_byte);
        end
    endfunction

    function automatic [7:0] expected_mode2_byte(
        input [7:0] old_byte,
        input       plane_host_bit,
        input [7:0] mask_byte,
        input [1:0] rop
    );
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            src_byte = {8{plane_host_bit}};
            alu_byte = apply_rop(old_byte, src_byte, rop);
            expected_mode2_byte = (alu_byte & mask_byte) | (old_byte & ~mask_byte);
        end
    endfunction

    function automatic [7:0] expected_mode3_byte(
        input [7:0] old_byte,
        input [7:0] host_byte,
        input       plane_set_reset,
        input [7:0] mask_byte,
        input [1:0] rop,
        input [2:0] rotate_count_sel
    );
        reg [7:0] rotated_host_byte;
        reg [7:0] effective_mask;
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            rotated_host_byte = rotate_right8(host_byte, rotate_count_sel);
            effective_mask = rotated_host_byte & mask_byte;
            src_byte = {8{plane_set_reset}};
            alu_byte = apply_rop(old_byte, src_byte, rop);
            expected_mode3_byte = (alu_byte & effective_mask) | (old_byte & ~effective_mask);
        end
    endfunction

    function automatic [7:0] expected_read_mode1(
        input [7:0] plane0_byte,
        input [7:0] plane1_byte,
        input [7:0] plane2_byte,
        input [7:0] plane3_byte,
        input [7:0] compare_byte,
        input [7:0] dont_care_byte
    );
        reg [7:0] temp;
        reg [7:0] temp2;
        reg [7:0] temp3;
        reg [7:0] temp4;
        begin
            temp = plane0_byte;
            temp = temp ^ ((compare_byte & 8'h01) ? 8'hFF : 8'h00);
            temp = temp & ((dont_care_byte & 8'h01) ? 8'hFF : 8'h00);
            temp2 = plane1_byte;
            temp2 = temp2 ^ ((compare_byte & 8'h02) ? 8'hFF : 8'h00);
            temp2 = temp2 & ((dont_care_byte & 8'h02) ? 8'hFF : 8'h00);
            temp3 = plane2_byte;
            temp3 = temp3 ^ ((compare_byte & 8'h04) ? 8'hFF : 8'h00);
            temp3 = temp3 & ((dont_care_byte & 8'h04) ? 8'hFF : 8'h00);
            temp4 = plane3_byte;
            temp4 = temp4 ^ ((compare_byte & 8'h08) ? 8'hFF : 8'h00);
            temp4 = temp4 & ((dont_care_byte & 8'h08) ? 8'hFF : 8'h00);
            expected_read_mode1 = ~(temp | temp2 | temp3 | temp4);
        end
    endfunction

    function automatic [15:0] expected_cpu_plane_addr(
        input [16:0] addr,
        input        odd_even_mode_sel,
        input        extended_memory_sel,
        input [1:0]  mem_map_sel_in,
        input        page_select_in
    );
        reg [15:0] remapped_addr;
        reg [2:0]  a0mux;
        begin
            remapped_addr = addr[15:0];
            a0mux = 3'b000;

            if (odd_even_mode_sel)
                a0mux = a0mux | 3'b010;

            if (mem_map_sel_in == 2'b00)
                a0mux = a0mux | 3'b100;

            case (mem_map_sel_in)
                2'b10,
                2'b11: remapped_addr = remapped_addr & 16'h7FFF;
                default: remapped_addr = remapped_addr & 16'hFFFF;
            endcase

            case (a0mux)
                3'b010: begin
                    remapped_addr = remapped_addr & 16'hFFFE;
                    remapped_addr[0] = ~page_select_in;
                end
                3'b110: begin
                    remapped_addr = remapped_addr & 16'hFFFE;
                    remapped_addr[0] = addr[16];
                end
                default: begin
                end
            endcase

            if (!extended_memory_sel)
                remapped_addr = remapped_addr & 16'h3FFF;

            expected_cpu_plane_addr = remapped_addr;
        end
    endfunction

    function automatic [1:0] expected_read_plane(
        input [16:0] addr,
        input [1:0]  read_plane,
        input        chain2_read_sel
    );
        begin
            expected_read_plane = chain2_read_sel ? {read_plane[1], addr[0]} : read_plane;
        end
    endfunction

    function automatic [3:0] expected_write_mask(
        input [16:0] addr,
        input [3:0]  mask,
        input        chain2_write_sel
    );
        begin
            expected_write_mask = chain2_write_sel ? (mask & (4'b0101 << addr[0])) : mask;
        end
    endfunction

    function automatic [16:0] ega_abs_to_offset(input [19:0] abs_addr);
        begin
            ega_abs_to_offset = (abs_addr - 20'hA0000) & 17'h1FFFF;
        end
    endfunction

    function automatic expected_cpu_window_select(
        input [19:0] abs_addr,
        input [1:0]  map_sel
    );
        begin
            case (map_sel)
                2'b00: expected_cpu_window_select = (abs_addr >= 20'hA0000) && (abs_addr <= 20'hBFFFF);
                2'b01: expected_cpu_window_select = (abs_addr >= 20'hA0000) && (abs_addr <= 20'hAFFFF);
                2'b10: expected_cpu_window_select = (abs_addr >= 20'hB0000) && (abs_addr <= 20'hB7FFF);
                2'b11: expected_cpu_window_select = (abs_addr >= 20'hB8000) && (abs_addr <= 20'hBFFFF);
                default: expected_cpu_window_select = 1'b0;
            endcase
        end
    endfunction

    task automatic expect_eq8(
        input [8*48-1:0] label,
        input [7:0] actual,
        input [7:0] expected
    );
        begin
            if (actual !== expected) begin
                failures = failures + 1;
                $display(
                    "FAIL test=%0s check=%0s expected=%02h actual=%02h cpu_addr=%05h cpu_re=%0b cpu_we=%0b mem_sel=%0b rd_mode=%0d wr_mode=%0d mem_map=%0d page=%0b mask=%04b odd_even=%0b chain2_rd=%0b chain2_wr=%0b",
                    current_test,
                    label,
                    expected,
                    actual,
                    {cpu_a16, cpu_addr},
                    cpu_re,
                    cpu_we,
                    cpu_mem_select,
                    read_mode,
                    write_mode,
                    mem_map_sel,
                    page_select,
                    plane_write_mask,
                    odd_even_mode,
                    chain2_read,
                    chain2_write
                );
            end
        end
    endtask

    task automatic begin_test(input [8*64-1:0] label);
        begin
            current_test = label;
            $display("TEST: %0s", current_test);
        end
    endtask

    task automatic reset_inputs;
        begin
            cpu_addr = 16'h0000;
            cpu_a16 = 1'b0;
            cpu_data_in = 8'h00;
            cpu_we = 1'b0;
            cpu_re = 1'b0;
            cpu_mem_select = 1'b0;
            plane_write_mask = 4'h0;
            odd_even_mode = 1'b0;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            color_compare = 8'h00;
            color_dont_care = 8'h0F;
            bit_mask = 8'hFF;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;
            rop_select = 2'b00;
            rotate_count = 3'b000;
            crt_addr = 16'h0000;
            crt_re = 1'b0;
            text_cell_addr = 16'h0000;
            text_font_addr = 16'h0000;
            text_re = 1'b0;
        end
    endtask

    task automatic set_planes(
        input [15:0] addr,
        input [7:0] plane0_byte,
        input [7:0] plane1_byte,
        input [7:0] plane2_byte,
        input [7:0] plane3_byte
    );
        begin
            dut.plane0[addr] = plane0_byte;
            dut.plane1[addr] = plane1_byte;
            dut.plane2[addr] = plane2_byte;
            dut.plane3[addr] = plane3_byte;
        end
    endtask

    task automatic crt_read_tx(input [15:0] addr);
        begin
            @(negedge clk_vram);
            crt_addr = addr;
            crt_re = 1'b1;
            @(posedge clk_vram);
            @(negedge clk_vram);
            crt_re = 1'b0;
        end
    endtask

    task automatic text_read_tx(input [15:0] cell_addr, input [15:0] font_addr);
        begin
            @(negedge clk_vram);
            text_cell_addr = cell_addr;
            text_font_addr = font_addr;
            text_re = 1'b1;
            @(posedge clk_vram);
            @(negedge clk_vram);
            text_re = 1'b0;
        end
    endtask

    task automatic cpu_read_tx(input [16:0] addr);
        begin
            @(negedge clk);
            cpu_addr = addr[15:0];
            cpu_a16 = addr[16];
            cpu_re = 1'b1;
            cpu_we = 1'b0;
            cpu_mem_select = 1'b1;
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            cpu_re = 1'b0;
            cpu_mem_select = 1'b0;
        end
    endtask

    task automatic cpu_write_tx(
        input [16:0] addr,
        input [7:0] data
    );
        begin
            cpu_write_select_tx(addr, data, 1'b1);
        end
    endtask

    task automatic cpu_write_select_tx(
        input [16:0] addr,
        input [7:0] data,
        input        mem_select
    );
        begin
            @(negedge clk);
            cpu_addr = addr[15:0];
            cpu_a16 = addr[16];
            cpu_data_in = data;
            cpu_re = 1'b0;
            cpu_we = 1'b1;
            cpu_mem_select = mem_select;
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            cpu_we = 1'b0;
            cpu_mem_select = 1'b0;
        end
    endtask

    task automatic cpu_write_abs_tx(
        input [19:0] abs_addr,
        input [7:0]  data
    );
        begin
            cpu_write_select_tx(
                ega_abs_to_offset(abs_addr),
                data,
                expected_cpu_window_select(abs_addr, mem_map_sel)
            );
        end
    endtask

    task automatic test_latches_and_write_mode1;
        begin
            begin_test("latches and write mode 1");
            set_planes(14'h0001, 8'h12, 8'h34, 8'h56, 8'h78);
            set_planes(14'h0002, 8'hAA, 8'hBB, 8'hCC, 8'hDD);
            set_planes(14'h0003, 8'h11, 8'h22, 8'h33, 8'h44);

            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            cpu_read_tx(16'h0001);

            expect_eq8("latch plane0 after read", latch_plane0, 8'h12);
            expect_eq8("latch plane1 after read", latch_plane1, 8'h34);
            expect_eq8("latch plane2 after read", latch_plane2, 8'h56);
            expect_eq8("latch plane3 after read", latch_plane3, 8'h78);
            expect_eq8("read plane0 data", cpu_data_out, 8'h12);

            write_mode = 2'b00;
            plane_write_mask = 4'hF;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'b000;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;
            cpu_write_tx(16'h0003, 8'hE1);

            expect_eq8("latch plane0 unchanged on write", latch_plane0, 8'h12);
            expect_eq8("latch plane1 unchanged on write", latch_plane1, 8'h34);
            expect_eq8("latch plane2 unchanged on write", latch_plane2, 8'h56);
            expect_eq8("latch plane3 unchanged on write", latch_plane3, 8'h78);

            write_mode = 2'b01;
            plane_write_mask = 4'hF;
            cpu_write_tx(16'h0002, 8'h00);

            expect_eq8("write mode1 plane0", dut.plane0[14'h0002], 8'h12);
            expect_eq8("write mode1 plane1", dut.plane1[14'h0002], 8'h34);
            expect_eq8("write mode1 plane2", dut.plane2[14'h0002], 8'h56);
            expect_eq8("write mode1 plane3", dut.plane3[14'h0002], 8'h78);
            expect_eq8("debug old plane0 mode1", debug_old_plane0, 8'hAA);
            expect_eq8("debug new plane0 mode1", debug_new_plane0, 8'h12);
        end
    endtask

    task automatic test_write_modes_0_and_2;
        reg [7:0] expected0;
        reg [7:0] expected1;
        reg [7:0] expected2;
        reg [7:0] expected3;
        begin
            begin_test("write modes 0 and 2");

            set_planes(14'h0010, 8'h3C, 8'hC3, 8'h5A, 8'hA5);
            plane_write_mask = 4'hF;
            write_mode = 2'b00;
            bit_mask = 8'h3C;
            set_reset = 8'h0A;
            enable_set_reset = 4'b0101;
            rop_select = 2'b11;
            rotate_count = 3'd3;

            expected0 = expected_mode0_byte(8'h3C, 8'h96, set_reset[0], enable_set_reset[0], bit_mask, rop_select, rotate_count);
            expected1 = expected_mode0_byte(8'hC3, 8'h96, set_reset[1], enable_set_reset[1], bit_mask, rop_select, rotate_count);
            expected2 = expected_mode0_byte(8'h5A, 8'h96, set_reset[2], enable_set_reset[2], bit_mask, rop_select, rotate_count);
            expected3 = expected_mode0_byte(8'hA5, 8'h96, set_reset[3], enable_set_reset[3], bit_mask, rop_select, rotate_count);
            cpu_write_tx(16'h0010, 8'h96);

            expect_eq8("write mode0 plane0", dut.plane0[14'h0010], expected0);
            expect_eq8("write mode0 plane1", dut.plane1[14'h0010], expected1);
            expect_eq8("write mode0 plane2", dut.plane2[14'h0010], expected2);
            expect_eq8("write mode0 plane3", dut.plane3[14'h0010], expected3);

            set_planes(14'h0011, 8'h0F, 8'hF0, 8'h55, 8'hAA);
            plane_write_mask = 4'hF;
            write_mode = 2'b10;
            bit_mask = 8'h5A;
            rop_select = 2'b10;
            rotate_count = 3'd0;

            expected0 = expected_mode2_byte(8'h0F, 1'b1, bit_mask, rop_select);
            expected1 = expected_mode2_byte(8'hF0, 1'b0, bit_mask, rop_select);
            expected2 = expected_mode2_byte(8'h55, 1'b1, bit_mask, rop_select);
            expected3 = expected_mode2_byte(8'hAA, 1'b0, bit_mask, rop_select);
            cpu_write_tx(16'h0011, 8'h05);

            expect_eq8("write mode2 plane0", dut.plane0[14'h0011], expected0);
            expect_eq8("write mode2 plane1", dut.plane1[14'h0011], expected1);
            expect_eq8("write mode2 plane2", dut.plane2[14'h0011], expected2);
            expect_eq8("write mode2 plane3", dut.plane3[14'h0011], expected3);
        end
    endtask

    task automatic test_write_mode3_and_map_mask;
        reg [7:0] expected0;
        reg [7:0] expected1;
        reg [7:0] expected2;
        reg [7:0] expected3;
        begin
            begin_test("write mode 3 and map mask");
            odd_even_mode = 1'b0;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            mem_map_sel = 2'b01;
            page_select = 1'b0;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            set_planes(14'h0012, 8'h18, 8'h28, 8'h38, 8'h48);
            plane_write_mask = 4'b0101;
            write_mode = 2'b00;
            bit_mask = 8'hF0;
            rop_select = 2'b01;
            rotate_count = 3'd1;
            expected0 = expected_mode0_byte(8'h18, 8'h3C, set_reset[0], enable_set_reset[0], bit_mask, rop_select, rotate_count);
            expected2 = expected_mode0_byte(8'h38, 8'h3C, set_reset[2], enable_set_reset[2], bit_mask, rop_select, rotate_count);
            cpu_write_tx(16'h0012, 8'h3C);
            expect_eq8("write mode0 masked plane0", dut.plane0[14'h0012], expected0);
            expect_eq8("write mode0 mask keeps plane1", dut.plane1[14'h0012], 8'h28);
            expect_eq8("write mode0 masked plane2", dut.plane2[14'h0012], expected2);
            expect_eq8("write mode0 mask keeps plane3", dut.plane3[14'h0012], 8'h48);

            set_planes(14'h0013, 8'h19, 8'h29, 8'h39, 8'h49);
            plane_write_mask = 4'hF;
            write_mode = 2'b11;
            bit_mask = 8'hFF;
            rop_select = 2'b11;
            rotate_count = 3'd4;
            set_reset = 8'h0F;
            enable_set_reset = 4'hF;
            expected0 = expected_mode3_byte(8'h19, 8'hA5, set_reset[0], bit_mask, rop_select, rotate_count);
            expected1 = expected_mode3_byte(8'h29, 8'hA5, set_reset[1], bit_mask, rop_select, rotate_count);
            expected2 = expected_mode3_byte(8'h39, 8'hA5, set_reset[2], bit_mask, rop_select, rotate_count);
            expected3 = expected_mode3_byte(8'h49, 8'hA5, set_reset[3], bit_mask, rop_select, rotate_count);
            cpu_write_tx(16'h0013, 8'hA5);
            expect_eq8("write mode3 plane0", dut.plane0[14'h0013], expected0);
            expect_eq8("write mode3 plane1", dut.plane1[14'h0013], expected1);
            expect_eq8("write mode3 plane2", dut.plane2[14'h0013], expected2);
            expect_eq8("write mode3 plane3", dut.plane3[14'h0013], expected3);
        end
    endtask

    task automatic test_read_mode1;
        reg [7:0] expected;
        begin
            begin_test("read mode 1");
            odd_even_mode = 1'b0;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            mem_map_sel = 2'b01;
            page_select = 1'b0;
            set_planes(14'h0020, 8'hF0, 8'hCC, 8'hAA, 8'h81);
            read_mode = 2'b01;
            color_compare = 8'h05;
            color_dont_care = 8'h0D;
            expected = expected_read_mode1(8'hF0, 8'hCC, 8'hAA, 8'h81, color_compare, color_dont_care);

            cpu_read_tx(16'h0020);

            expect_eq8("read mode1 result", cpu_data_out, expected);
            expect_eq8("read mode1 latch plane0", latch_plane0, 8'hF0);
            expect_eq8("read mode1 latch plane3", latch_plane3, 8'h81);

            set_planes(14'h0021, 8'h0F, 8'h33, 8'h55, 8'h7E);
            color_compare = 8'h0A;
            color_dont_care = 8'h05;
            expected = expected_read_mode1(8'h0F, 8'h33, 8'h55, 8'h7E, color_compare, color_dont_care);
            cpu_read_tx(16'h0021);
            expect_eq8("read mode1 masked compare", cpu_data_out, expected);
            expect_eq8("read mode1 masked latch0", latch_plane0, 8'h0F);
            expect_eq8("read mode1 masked latch3", latch_plane3, 8'h7E);
        end
    endtask

    task automatic test_read_mode0_plane_select;
        begin
            begin_test("read mode 0 plane select and latches");
            odd_even_mode = 1'b0;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            mem_map_sel = 2'b01;
            page_select = 1'b0;
            read_mode = 2'b00;

            set_planes(14'h0024, 8'h12, 8'h34, 8'h56, 8'h78);
            read_plane_sel = 2'b00;
            cpu_read_tx(16'h0024);
            expect_eq8("read mode0 plane0", cpu_data_out, 8'h12);
            expect_eq8("read mode0 latch0 p0", latch_plane0, 8'h12);
            expect_eq8("read mode0 latch0 p3", latch_plane3, 8'h78);

            read_plane_sel = 2'b01;
            cpu_read_tx(16'h0024);
            expect_eq8("read mode0 plane1", cpu_data_out, 8'h34);
            expect_eq8("read mode0 latch1 p1", latch_plane1, 8'h34);

            read_plane_sel = 2'b10;
            cpu_read_tx(16'h0024);
            expect_eq8("read mode0 plane2", cpu_data_out, 8'h56);
            expect_eq8("read mode0 latch2 p2", latch_plane2, 8'h56);

            read_plane_sel = 2'b11;
            cpu_read_tx(16'h0024);
            expect_eq8("read mode0 plane3", cpu_data_out, 8'h78);
            expect_eq8("read mode0 latch3 p3", latch_plane3, 8'h78);

            set_planes(14'h0025, 8'h9A, 8'hBC, 8'hDE, 8'hF0);
            read_plane_sel = 2'b10;
            cpu_read_tx(16'h0025);
            expect_eq8("read mode0 second plane2", cpu_data_out, 8'hDE);
            expect_eq8("read mode0 second latch0", latch_plane0, 8'h9A);
            expect_eq8("read mode0 second latch1", latch_plane1, 8'hBC);
            expect_eq8("read mode0 second latch2", latch_plane2, 8'hDE);
            expect_eq8("read mode0 second latch3", latch_plane3, 8'hF0);
        end
    endtask

    task automatic test_consecutive_writes;
        begin
            begin_test("consecutive writes keep address/data aligned");
            plane_write_mask = 4'hF;
            write_mode = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            set_planes(14'h0030, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(14'h0031, 8'h00, 8'h00, 8'h00, 8'h00);

            cpu_write_tx(16'h0030, 8'h3C);
            cpu_write_tx(16'h0031, 8'hC3);

            expect_eq8("consecutive write addr0 plane0", dut.plane0[14'h0030], 8'h3C);
            expect_eq8("consecutive write addr0 plane3", dut.plane3[14'h0030], 8'h3C);
            expect_eq8("consecutive write addr1 plane0", dut.plane0[14'h0031], 8'hC3);
            expect_eq8("consecutive write addr1 plane3", dut.plane3[14'h0031], 8'hC3);
            expect_eq8("debug old plane0 second write", debug_old_plane0, 8'h00);
            expect_eq8("debug new plane0 second write", debug_new_plane0, 8'hC3);
        end
    endtask

    task automatic test_cpu_a16_remap;
        reg [15:0] low_addr;
        reg [15:0] high_addr;
        begin
            begin_test("CPU A16 selects remapped low/high A000 aperture bytes");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b1;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            mem_map_sel = 2'b00;
            page_select = 1'b0;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            low_addr = expected_cpu_plane_addr(17'h00040, odd_even_mode, extended_memory, mem_map_sel, page_select);
            high_addr = expected_cpu_plane_addr(17'h10040, odd_even_mode, extended_memory, mem_map_sel, page_select);

            expect_eq8("cpu a16=0 expected remap address", low_addr[7:0], 8'h40);
            expect_eq8("cpu a16=1 expected remap address", high_addr[7:0], 8'h41);
            expect_eq8("chain2 disabled read plane", {6'b000000, expected_read_plane(17'h10040, read_plane_sel, chain2_read)}, 8'h00);
            expect_eq8("chain2 disabled write mask", {4'b0000, expected_write_mask(17'h10040, plane_write_mask, chain2_write)}, 8'h0F);

            set_planes(low_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(high_addr, 8'h00, 8'h00, 8'h00, 8'h00);

            cpu_write_tx(17'h00040, 8'hA5);
            cpu_write_tx(17'h10040, 8'h5A);

            expect_eq8("cpu a16=0 write maps to even remap byte", dut.plane0[low_addr], 8'hA5);
            expect_eq8("cpu a16=1 write maps to odd remap byte", dut.plane0[high_addr], 8'h5A);

            cpu_read_tx(17'h00040);
            expect_eq8("cpu a16=0 read plane0", cpu_data_out, 8'hA5);

            cpu_read_tx(17'h10040);
            expect_eq8("cpu a16=1 read plane0", cpu_data_out, 8'h5A);
        end
    endtask

    task automatic test_chain2_read_write;
        reg [15:0] even_addr;
        reg [15:0] odd_addr;
        reg [15:0] masked_addr;
        reg [15:0] a16_addr;
        reg [15:0] page_addr;
        begin
            begin_test("chain-2 read/write plane selection");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b0;
            chain2_write = 1'b1;
            chain2_read = 1'b1;
            extended_memory = 1'b1;
            mem_map_sel = 2'b01;
            page_select = 1'b0;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            even_addr = expected_cpu_plane_addr(17'h00050, odd_even_mode, extended_memory, mem_map_sel, page_select);
            odd_addr = expected_cpu_plane_addr(17'h00051, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("chain2 even read plane", {6'b000000, expected_read_plane(17'h00050, read_plane_sel, chain2_read)}, 8'h00);
            expect_eq8("chain2 odd read plane", {6'b000000, expected_read_plane(17'h00051, read_plane_sel, chain2_read)}, 8'h01);
            expect_eq8("chain2 even write mask", {4'b0000, expected_write_mask(17'h00050, plane_write_mask, chain2_write)}, 8'h05);
            expect_eq8("chain2 odd write mask", {4'b0000, expected_write_mask(17'h00051, plane_write_mask, chain2_write)}, 8'h0A);

            set_planes(even_addr, 8'h10, 8'h20, 8'h30, 8'h40);
            set_planes(odd_addr, 8'h11, 8'h21, 8'h31, 8'h41);
            cpu_write_tx(17'h00050, 8'hA0);
            cpu_write_tx(17'h00051, 8'hB1);
            expect_eq8("chain2 even writes plane0", dut.plane0[even_addr], 8'hA0);
            expect_eq8("chain2 even keeps plane1", dut.plane1[even_addr], 8'h20);
            expect_eq8("chain2 even writes plane2", dut.plane2[even_addr], 8'hA0);
            expect_eq8("chain2 even keeps plane3", dut.plane3[even_addr], 8'h40);
            expect_eq8("chain2 odd keeps plane0", dut.plane0[odd_addr], 8'h11);
            expect_eq8("chain2 odd writes plane1", dut.plane1[odd_addr], 8'hB1);
            expect_eq8("chain2 odd keeps plane2", dut.plane2[odd_addr], 8'h31);
            expect_eq8("chain2 odd writes plane3", dut.plane3[odd_addr], 8'hB1);

            read_plane_sel = 2'b00;
            cpu_read_tx(17'h00050);
            expect_eq8("chain2 read even plane0", cpu_data_out, 8'hA0);
            cpu_read_tx(17'h00051);
            expect_eq8("chain2 read odd plane1", cpu_data_out, 8'hB1);
            read_plane_sel = 2'b10;
            cpu_read_tx(17'h00050);
            expect_eq8("chain2 read even plane2", cpu_data_out, 8'hA0);
            cpu_read_tx(17'h00051);
            expect_eq8("chain2 read odd plane3", cpu_data_out, 8'hB1);

            plane_write_mask = 4'b0111;
            masked_addr = expected_cpu_plane_addr(17'h00053, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("chain2 masked odd write mask", {4'b0000, expected_write_mask(17'h00053, plane_write_mask, chain2_write)}, 8'h02);
            set_planes(masked_addr, 8'h12, 8'h22, 8'h32, 8'h42);
            cpu_write_tx(17'h00053, 8'hC3);
            expect_eq8("chain2 mask keeps plane0", dut.plane0[masked_addr], 8'h12);
            expect_eq8("chain2 mask writes plane1", dut.plane1[masked_addr], 8'hC3);
            expect_eq8("chain2 mask keeps plane2", dut.plane2[masked_addr], 8'h32);
            expect_eq8("chain2 mask keeps plane3", dut.plane3[masked_addr], 8'h42);

            plane_write_mask = 4'hF;
            mem_map_sel = 2'b00;
            odd_even_mode = 1'b1;
            page_select = 1'b0;
            read_plane_sel = 2'b00;
            a16_addr = expected_cpu_plane_addr(17'h10060, odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(a16_addr, 8'h13, 8'h23, 8'h33, 8'h43);
            cpu_write_tx(17'h10060, 8'hD4);
            expect_eq8("chain2 a16 remap address", a16_addr[7:0], 8'h61);
            expect_eq8("chain2 a16 writes plane0", dut.plane0[a16_addr], 8'hD4);
            expect_eq8("chain2 a16 writes plane2", dut.plane2[a16_addr], 8'hD4);
            cpu_read_tx(17'h10060);
            expect_eq8("chain2 a16 read plane0", cpu_data_out, 8'hD4);

            mem_map_sel = 2'b01;
            odd_even_mode = 1'b1;
            page_select = 1'b0;
            page_addr = expected_cpu_plane_addr(17'h00070, odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(page_addr, 8'h14, 8'h24, 8'h34, 8'h44);
            cpu_write_tx(17'h00070, 8'hE5);
            expect_eq8("chain2 page remap address", page_addr[7:0], 8'h71);
            expect_eq8("chain2 page writes plane0", dut.plane0[page_addr], 8'hE5);
            expect_eq8("chain2 page writes plane2", dut.plane2[page_addr], 8'hE5);
            cpu_read_tx(17'h00070);
            expect_eq8("chain2 page read plane0", cpu_data_out, 8'hE5);
        end
    endtask

    task automatic test_odd_even_page_select;
        reg [15:0] page_even_addr;
        reg [15:0] page_odd_addr;
        reg [15:0] bank_low_addr;
        reg [15:0] bank_high_addr;
        reg [15:0] ext_mask_addr;
        begin
            begin_test("odd/even page select address remap");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b1;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            mem_map_sel = 2'b01;
            page_select = 1'b1;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            page_even_addr = expected_cpu_plane_addr(17'h00080, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("page select 1 forces even addr", page_even_addr[7:0], 8'h80);
            set_planes(page_even_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_tx(17'h00080, 8'h66);
            expect_eq8("page select 1 write plane0", dut.plane0[page_even_addr], 8'h66);
            cpu_read_tx(17'h00080);
            expect_eq8("page select 1 read plane0", cpu_data_out, 8'h66);

            page_select = 1'b0;
            page_odd_addr = expected_cpu_plane_addr(17'h00080, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("page select 0 forces odd addr", page_odd_addr[7:0], 8'h81);
            set_planes(page_odd_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_tx(17'h00080, 8'h77);
            expect_eq8("page select 0 write plane0", dut.plane0[page_odd_addr], 8'h77);
            cpu_read_tx(17'h00080);
            expect_eq8("page select 0 read plane0", cpu_data_out, 8'h77);

            mem_map_sel = 2'b00;
            page_select = 1'b0;
            bank_low_addr = expected_cpu_plane_addr(17'h00090, odd_even_mode, extended_memory, mem_map_sel, page_select);
            bank_high_addr = expected_cpu_plane_addr(17'h10090, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("odd/even a16 low bank addr", bank_low_addr[7:0], 8'h90);
            expect_eq8("odd/even a16 high bank addr", bank_high_addr[7:0], 8'h91);
            set_planes(bank_low_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(bank_high_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_tx(17'h00090, 8'h88);
            cpu_write_tx(17'h10090, 8'h99);
            expect_eq8("odd/even a16 low write", dut.plane0[bank_low_addr], 8'h88);
            expect_eq8("odd/even a16 high write", dut.plane0[bank_high_addr], 8'h99);
            cpu_read_tx(17'h00090);
            expect_eq8("odd/even a16 low read", cpu_data_out, 8'h88);
            cpu_read_tx(17'h10090);
            expect_eq8("odd/even a16 high read", cpu_data_out, 8'h99);

            mem_map_sel = 2'b01;
            page_select = 1'b1;
            extended_memory = 1'b0;
            ext_mask_addr = expected_cpu_plane_addr(17'h08082, odd_even_mode, extended_memory, mem_map_sel, page_select);
            expect_eq8("odd/even ext memory mask addr", ext_mask_addr[7:0], 8'h82);
            set_planes(ext_mask_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_tx(17'h08082, 8'hAA);
            expect_eq8("odd/even ext mask write", dut.plane0[ext_mask_addr], 8'hAA);
            cpu_read_tx(17'h08082);
            expect_eq8("odd/even ext mask read", cpu_data_out, 8'hAA);
        end
    endtask

    task automatic test_crt_fetch_ignores_cpu_odd_even;
        reg [15:0] visible_addr;
        reg [15:0] remapped_cpu_addr;
        begin
            begin_test("CRT fetch ignores CPU odd/even remap");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b1;
            chain2_write = 1'b1;
            chain2_read = 1'b1;
            extended_memory = 1'b1;
            mem_map_sel = 2'b00;
            page_select = 1'b0;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            visible_addr = 16'h0120;
            remapped_cpu_addr = expected_cpu_plane_addr(
                {1'b1, visible_addr},
                odd_even_mode,
                extended_memory,
                mem_map_sel,
                page_select
            );

            expect_eq8("cpu odd/even would remap address", remapped_cpu_addr[7:0], 8'h21);
            set_planes(visible_addr, 8'h10, 8'h20, 8'h30, 8'h40);
            set_planes(remapped_cpu_addr, 8'hA1, 8'hB2, 8'hC3, 8'hD4);

            crt_read_tx(visible_addr);

            expect_eq8("crt plane0 uses visible addr", crt_plane0, 8'h10);
            expect_eq8("crt plane1 uses visible addr", crt_plane1, 8'h20);
            expect_eq8("crt plane2 uses visible addr", crt_plane2, 8'h30);
            expect_eq8("crt plane3 uses visible addr", crt_plane3, 8'h40);

            cpu_read_tx({1'b1, visible_addr});
            expect_eq8("cpu plane0 still uses odd/even remap", cpu_data_out, 8'hA1);
        end
    endtask

    task automatic test_text_fetch_channel;
        reg [15:0] cell_addr;
        reg [15:0] font_addr;
        begin
            begin_test("Text fetch channel returns cell and font bytes");
            cell_addr = 16'h0220;
            font_addr = 16'h1847;

            set_planes(cell_addr, 8'h41, 8'h1E, 8'h99, 8'h55);
            set_planes(font_addr, 8'h00, 8'h00, 8'hA5, 8'h00);
            set_planes(16'h0333, 8'h00, 8'h00, 8'h00, 8'h77);
            crt_addr = 16'h0333;

            text_read_tx(cell_addr, font_addr);

            expect_eq8("text char from plane0 cell address", crt_plane0, 8'h41);
            expect_eq8("text attr from plane1 cell address", crt_plane1, 8'h1E);
            expect_eq8("text glyph from plane2 font address", crt_plane2, 8'hA5);
            expect_eq8("text fetch leaves plane3 on CRT address", crt_plane3, 8'h77);

            crt_read_tx(cell_addr);
            expect_eq8("graphics CRT plane2 still uses visible address", crt_plane2, 8'h99);
        end
    endtask

    task automatic test_memory_map_windows;
        reg [15:0] map0_first_addr;
        reg [15:0] map0_last_addr;
        reg [15:0] map1_first_addr;
        reg [15:0] map1_last_addr;
        reg [15:0] map2_first_addr;
        reg [15:0] map2_last_addr;
        reg [15:0] map3_first_addr;
        reg [15:0] map3_last_addr;
        begin
            begin_test("GC memory map window selection");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b0;
            chain2_write = 1'b0;
            chain2_read = 1'b0;
            extended_memory = 1'b1;
            page_select = 1'b0;
            write_mode = 2'b00;
            read_mode = 2'b00;
            read_plane_sel = 2'b00;
            bit_mask = 8'hFF;
            rop_select = 2'b00;
            rotate_count = 3'd0;
            set_reset = 8'h00;
            enable_set_reset = 4'h0;

            mem_map_sel = 2'b00;
            map0_first_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hA0000), odd_even_mode, extended_memory, mem_map_sel, page_select);
            map0_last_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hBFFFF), odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(map0_first_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(map0_last_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_abs_tx(20'hA0000, 8'h10);
            cpu_write_abs_tx(20'hBFFFF, 8'h11);
            cpu_write_abs_tx(20'hC0000, 8'hEE);
            expect_eq8("map0 accepts A0000h", dut.plane0[map0_first_addr], 8'h10);
            expect_eq8("map0 accepts BFFFFh", dut.plane0[map0_last_addr], 8'h11);
            expect_eq8("map0 ignores C0000h", dut.plane0[map0_first_addr], 8'h10);

            mem_map_sel = 2'b01;
            map1_first_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hA0000), odd_even_mode, extended_memory, mem_map_sel, page_select);
            map1_last_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hAFFFF), odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(map1_first_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(map1_last_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_abs_tx(20'hA0000, 8'h20);
            cpu_write_abs_tx(20'hAFFFF, 8'h21);
            cpu_write_abs_tx(20'hB0000, 8'hEE);
            expect_eq8("map1 accepts A0000h", dut.plane0[map1_first_addr], 8'h20);
            expect_eq8("map1 accepts AFFFFh", dut.plane0[map1_last_addr], 8'h21);
            expect_eq8("map1 ignores B0000h", dut.plane0[map1_first_addr], 8'h20);

            mem_map_sel = 2'b10;
            map2_first_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hB0000), odd_even_mode, extended_memory, mem_map_sel, page_select);
            map2_last_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hB7FFF), odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(map2_first_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(map2_last_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_abs_tx(20'hB0000, 8'h30);
            cpu_write_abs_tx(20'hB7FFF, 8'h31);
            cpu_write_abs_tx(20'hAFFFF, 8'hEE);
            expect_eq8("map2 accepts B0000h", dut.plane0[map2_first_addr], 8'h30);
            expect_eq8("map2 accepts B7FFFh", dut.plane0[map2_last_addr], 8'h31);
            expect_eq8("map2 ignores AFFFFh", dut.plane0[map2_last_addr], 8'h31);

            mem_map_sel = 2'b11;
            map3_first_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hB8000), odd_even_mode, extended_memory, mem_map_sel, page_select);
            map3_last_addr = expected_cpu_plane_addr(ega_abs_to_offset(20'hBFFFF), odd_even_mode, extended_memory, mem_map_sel, page_select);
            set_planes(map3_first_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(map3_last_addr, 8'h00, 8'h00, 8'h00, 8'h00);
            cpu_write_abs_tx(20'hB8000, 8'h40);
            cpu_write_abs_tx(20'hBFFFF, 8'h41);
            cpu_write_abs_tx(20'hB7FFF, 8'hEE);
            expect_eq8("map3 accepts B8000h", dut.plane0[map3_first_addr], 8'h40);
            expect_eq8("map3 accepts BFFFFh", dut.plane0[map3_last_addr], 8'h41);
            expect_eq8("map3 ignores B7FFFh", dut.plane0[map3_last_addr], 8'h41);
        end
    endtask

    initial begin
        reset_inputs();
        repeat (4) @(posedge clk);

        test_latches_and_write_mode1();
        test_write_modes_0_and_2();
        test_write_mode3_and_map_mask();
        test_read_mode1();
        test_read_mode0_plane_select();
        test_consecutive_writes();
        test_cpu_a16_remap();
        test_chain2_read_write();
        test_odd_even_page_select();
        test_crt_fetch_ignores_cpu_odd_even();
        test_text_fetch_channel();
        test_memory_map_windows();

        if (failures != 0) begin
            $display("ega_vram_tb FAILED with %0d mismatches", failures);
            $finish(1);
        end

        $display("ega_vram_tb PASSED");
        $finish(0);
    end

endmodule
