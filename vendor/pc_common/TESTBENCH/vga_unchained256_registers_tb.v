`timescale 1ns/1ps

module vga_unchained256_registers_tb;
    reg clock = 1'b0;
    always #5 clock = ~clock;
    reg reset = 1'b1;
    reg [15:0] io_addr = 16'h0000;
    reg [7:0] io_data = 8'h00;
    reg io_we = 1'b0;
    reg io_re = 1'b0;
    wire [7:0] seq_data_out;
    wire [7:0] gfx_data_out;
    wire chain4;
    wire shift256;
    wire graphics_mode;
    wire [1:0] mem_map_sel;
    integer errors = 0;

    ega_sequencer seq (
        .clk(clock), .reset(reset), .ce_pix(1'b0), .ce_pix_early(1'b0),
        .io_addr(io_addr), .io_data_in(io_data), .io_data_out(seq_data_out),
        .io_we(io_we), .io_re(io_re), .plane_write_mask(),
        .chain2_write(), .chain4(chain4), .extended_memory(),
        .ce_crt_fetch(), .ce_crt_fetch_early(), .ce_cpu_access(),
        .dot_clock_div2(), .char_9dot(), .char_map_a(), .char_map_b(),
        .map_mask_debug(), .memory_mode_debug()
    );

    ega_gfx_ctrl gfx (
        .clk(clock), .reset(reset), .io_addr(io_addr), .io_data_in(io_data),
        .io_data_out(gfx_data_out), .io_we(io_we), .io_re(io_re),
        .write_mode(), .read_mode(), .read_plane_sel(), .color_compare(),
        .color_dont_care(), .bit_mask(), .set_reset(), .enable_set_reset(),
        .rop_select(), .rotate_count(), .odd_even_mode(), .chain2_read(),
        .graphics_mode(graphics_mode), .compat_2bpp_mode(),
        .shift256(shift256), .mem_map_sel(mem_map_sel), .mode_debug()
    );

    task write_port;
        input [15:0] addr;
        input [7:0] value;
        begin
            io_addr = addr; io_data = value; io_we = 1'b1;
            @(posedge clock); #1; io_we = 1'b0;
        end
    endtask

    task check_byte;
        input [7:0] actual;
        input [7:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s value=%02h expected=%02h", tag, actual, expected);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;

        write_port(16'h03C4, 8'h04);
        write_port(16'h03C5, 8'h0E);
        if (!chain4) begin errors = errors + 1; $display("FAIL: Chain-4 not set"); end
        io_addr = 16'h03C5; io_re = 1'b1; #1;
        check_byte(seq_data_out, 8'h0E, "Sequencer 04 readback");
        io_re = 1'b0;
        write_port(16'h03C5, 8'h06);
        if (chain4) begin errors = errors + 1; $display("FAIL: Chain-4 not cleared"); end

        write_port(16'h03CE, 8'h05);
        write_port(16'h03CF, 8'h40);
        if (!shift256) begin errors = errors + 1; $display("FAIL: Shift256 not set"); end
        io_addr = 16'h03CF; io_re = 1'b1; #1;
        check_byte(gfx_data_out, 8'h40, "Graphics Controller 05 readback");
        io_re = 1'b0;

        write_port(16'h03CE, 8'h06);
        write_port(16'h03CF, 8'h05);
        if (!graphics_mode || (mem_map_sel != 2'b01)) begin
            errors = errors + 1;
            $display("FAIL: GC 06 did not select graphics A000 aperture");
        end
        io_addr = 16'h03CF; io_re = 1'b1; #1;
        check_byte(gfx_data_out, 8'h05, "Graphics Controller 06 readback");

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
