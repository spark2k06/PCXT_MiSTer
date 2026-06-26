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

    task automatic expect_eq8(
        input [8*48-1:0] label,
        input [7:0] actual,
        input [7:0] expected
    );
        begin
            if (actual !== expected) begin
                failures = failures + 1;
                $display("FAIL %0s expected=%02h actual=%02h", label, expected, actual);
            end
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
            @(negedge clk);
            cpu_addr = addr[15:0];
            cpu_a16 = addr[16];
            cpu_data_in = data;
            cpu_re = 1'b0;
            cpu_we = 1'b1;
            cpu_mem_select = 1'b1;
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            cpu_we = 1'b0;
            cpu_mem_select = 1'b0;
        end
    endtask

    task automatic test_latches_and_write_mode1;
        begin
            $display("TEST: latches and write mode 1");
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
            $display("TEST: write modes 0 and 2");

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

    task automatic test_read_mode1;
        reg [7:0] expected;
        begin
            $display("TEST: read mode 1");
            set_planes(14'h0020, 8'hF0, 8'hCC, 8'hAA, 8'h81);
            read_mode = 2'b01;
            color_compare = 8'h05;
            color_dont_care = 8'h0D;
            expected = expected_read_mode1(8'hF0, 8'hCC, 8'hAA, 8'h81, color_compare, color_dont_care);

            cpu_read_tx(16'h0020);

            expect_eq8("read mode1 result", cpu_data_out, expected);
            expect_eq8("read mode1 latch plane0", latch_plane0, 8'hF0);
            expect_eq8("read mode1 latch plane3", latch_plane3, 8'h81);
        end
    endtask

    task automatic test_consecutive_writes;
        begin
            $display("TEST: consecutive writes keep address/data aligned");
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
        begin
            $display("TEST: CPU A16 selects remapped low/high A000 aperture bytes");
            plane_write_mask = 4'hF;
            odd_even_mode = 1'b0;
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

            set_planes(16'h0040, 8'h00, 8'h00, 8'h00, 8'h00);
            set_planes(16'h0041, 8'h00, 8'h00, 8'h00, 8'h00);

            cpu_write_tx(17'h00040, 8'hA5);
            cpu_write_tx(17'h10040, 8'h5A);

            expect_eq8("cpu a16=0 write maps to even remap byte", dut.plane0[16'h0040], 8'hA5);
            expect_eq8("cpu a16=1 write maps to odd remap byte", dut.plane0[16'h0041], 8'h5A);

            cpu_read_tx(17'h00040);
            expect_eq8("cpu a16=0 read plane0", cpu_data_out, 8'hA5);

            cpu_read_tx(17'h10040);
            expect_eq8("cpu a16=1 read plane0", cpu_data_out, 8'h5A);
        end
    endtask

    initial begin
        reset_inputs();
        repeat (4) @(posedge clk);

        test_latches_and_write_mode1();
        test_write_modes_0_and_2();
        test_read_mode1();
        test_consecutive_writes();
        test_cpu_a16_remap();

        if (failures != 0) begin
            $display("ega_vram_tb FAILED with %0d mismatches", failures);
            $finish(1);
        end

        $display("ega_vram_tb PASSED");
        $finish(0);
    end

endmodule
