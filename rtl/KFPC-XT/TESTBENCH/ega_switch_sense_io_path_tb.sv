//============================================================================
//
//  IBM EGA switch sense through the real ISA I/O path.
//
//  ROM 6277356 (offsets 009Bh-00CAh) writes 01h to 3C2h and then, two
//  instructions later, selects switches with 0Dh, 09h, 05h and 01h, reading
//  bit 4 back at the same port right after each selector. CGA 80 (07h) is the
//  sensitive case: if the very first selector - the 0Dh that follows the 01h
//  setup write almost immediately - is answered with the previous selector,
//  the ROM assembles 06h, which is precisely the CGA 40-column setting.
//
//  Two CPU models are exercised. The first honours access_ready, the way the
//  bus cycle does when the ready path stalls it. The second ignores it and
//  issues the OUT and the IN back to back, which is the worst case: any
//  implementation whose selector arrives through ega_io_stretch's posted
//  write - queued behind the preceding OUT - fails it. The switch sense is
//  taken from the live cycle precisely so that it does not.
//
//  The bench also holds ega_top to its half of the contract: 3C2h reads must
//  not be answered from the video clock domain at all.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_switch_sense_io_path_tb;

    logic clk50 = 1'b0;
    always #10.000 clk50 = ~clk50;

    logic clkv = 1'b0;
    always #17.462 clkv = ~clkv;

    logic reset = 1'b1;
    logic [14:0] cpu_addr = 15'd0;
    logic [7:0]  cpu_data = 8'd0;
    logic        cpu_iow_n = 1'b1;
    logic        cpu_ior_n = 1'b1;

    wire [14:0] posted_addr;
    wire [7:0]  posted_data;
    wire        posted_iow_n;
    wire        posted_ior_n;
    wire        posted_aen_n;
    wire        access_ready;

    ega_io_stretch bridge (
        .clock                  (clk50),
        .reset                  (reset),
        .io_write_n             (cpu_iow_n),
        .io_read_n              (cpu_ior_n),
        .address_enable_n       (1'b0),
        .address                (cpu_addr),
        .write_data             (cpu_data),
        .video_address          (posted_addr),
        .video_data             (posted_data),
        .video_io_write_n       (posted_iow_n),
        .video_io_read_n        (posted_ior_n),
        .video_address_enable_n (posted_aen_n),
        .access_ready           (access_ready)
    );

    logic [14:0] addr_meta, addr_sync;
    logic [7:0]  data_meta, data_sync;
    logic        iow_meta = 1'b1, iow_sync = 1'b1;
    logic        ior_meta = 1'b1, ior_sync = 1'b1;
    logic        aen_meta = 1'b1, aen_sync = 1'b1;

    always_ff @(posedge clkv or posedge reset) begin
        if (reset) begin
            addr_meta <= 15'd0;
            addr_sync <= 15'd0;
            data_meta <= 8'd0;
            data_sync <= 8'd0;
            iow_meta  <= 1'b1;
            iow_sync  <= 1'b1;
            ior_meta  <= 1'b1;
            ior_sync  <= 1'b1;
            aen_meta  <= 1'b1;
            aen_sync  <= 1'b1;
        end else begin
            addr_meta <= posted_addr;
            addr_sync <= addr_meta;
            data_meta <= posted_data;
            data_sync <= data_meta;
            iow_meta  <= posted_iow_n;
            iow_sync  <= iow_meta;
            ior_meta  <= posted_ior_n;
            ior_sync  <= ior_meta;
            aen_meta  <= posted_aen_n;
            aen_sync  <= aen_meta;
        end
    end

    wire [7:0] bus_out;
    wire       bus_dir;
    wire [7:0] host_data_out;
    wire       host_output_enable;

    ega_switch_sense_host host_path (
        .clock            (clk50),
        .reset            (reset),
        .monitor_profile  (2'd1),
        .io_address       (cpu_addr),
        .io_data          (cpu_data),
        .io_write_n       (cpu_iow_n),
        .io_read_n        (cpu_ior_n),
        .address_enable_n (1'b0),
        .data_out         (host_data_out),
        .output_enable    (host_output_enable)
    );

    ega_top dut (
        .clk                         (clkv),
        .reset                       (reset),
        .bus_a                       (addr_sync),
        .bus_ior_l                   (ior_sync),
        .bus_iow_l                   (iow_sync),
        .bus_d                       (data_sync),
        .bus_out                     (bus_out),
        .bus_dir                     (bus_dir),
        .bus_aen                     (aen_sync),
        .ega_plane0_data             (8'h00),
        .ega_plane1_data             (8'h00),
        .ega_plane2_data             (8'h00),
        .ega_plane3_data             (8'h00),
        .ega_fetch_data_valid        (1'b0),
        .ega_text_char               (8'h00),
        .ega_text_attr               (8'h00),
        .ega_text_glyph              (8'h00),
        .ega_text_data_valid         (1'b0),
        .ega_text_tag_in             (1'b0),
        .ext_splash_pixel_index      (4'd0),
        .ext_splash_pixel_valid      (1'b0),
        .prebios_video               (1'b0),
        .vga_framebuffer_pixel       (8'h00),
        .vga_framebuffer_data_valid  (1'b0),
        .cpu_mem_select              (1'b0),
        .cpu_mem_write               (1'b0),
        .splashscreen                (1'b0),
        .thin_font                   (1'b0),
        .scandouble_en               (1'b0),
        .ega_enabled                 (1'b1),
        .ega_monitor_profile         (2'd1),
        .vga_enabled                 (1'b0),
        .vga_mode13_set              (1'b0),
        .vga_mode13_clear            (1'b0),
        .crt_h_offset                (4'd0),
        .crt_v_offset                (3'd0),
        .vsync_width_osd             (3'd0),
        .hsync_width_osd             (3'd0)
    );

    integer errors = 0;

    // The shortest command pulse the chipset ever presents: three CPU
    // T-states plus the io_settle floor at the fastest speed setting.
    localparam int SHORT_CYCLE_TICKS = 6;

    // wait_ready = 1 models a CPU that is stalled by access_ready.
    // wait_ready = 0 models one that is not, and ends the cycle regardless.
    task automatic cpu_write(input logic [7:0] value, input bit wait_ready);
        begin
            @(posedge clk50);
            cpu_addr  <= 15'h03C2;
            cpu_data  <= value;
            cpu_iow_n <= 1'b0;
            if (wait_ready)
                do @(posedge clk50); while (!access_ready);
            else
                repeat (SHORT_CYCLE_TICKS) @(posedge clk50);
            cpu_iow_n <= 1'b1;
            // The 8088 releases IOW between OUT instructions, but the next
            // instruction may already present the same port on the next edge.
            @(posedge clk50);
        end
    endtask

    task automatic cpu_read_switch(input bit wait_ready, output logic host_value);
        begin
            @(posedge clk50);
            cpu_addr  <= 15'h03C2;
            // On a read the chipset drives the bus with its own reply, so the
            // data lines carry the returned status, not an OUT operand. The
            // selector must be indifferent to that.
            cpu_data  <= 8'h10;
            cpu_ior_n <= 1'b0;
            if (wait_ready)
                do @(posedge clk50); while (!access_ready);
            else
                repeat (SHORT_CYCLE_TICKS) @(posedge clk50);
            #1 host_value = host_data_out[4];
            if (!host_output_enable) begin
                errors = errors + 1;
                $display("FAIL: host switch read did not drive the ISA bus");
            end
            if (bus_dir) begin
                errors = errors + 1;
                $display("FAIL: ega_top answered a 3C2h read; Input Status 0 must come from the ISA domain only");
            end
            cpu_ior_n <= 1'b1;
            @(posedge clk50);
        end
    endtask

    task automatic read_switch_pattern(input bit wait_ready, output logic [3:0] pattern);
        begin
            // Exact ROM prologue and switch order at offsets 009Bh-00CAh.
            cpu_write(8'h01, wait_ready);
            cpu_write(8'h0D, wait_ready);
            cpu_read_switch(wait_ready, pattern[0]);
            cpu_write(8'h09, wait_ready);
            cpu_read_switch(wait_ready, pattern[1]);
            cpu_write(8'h05, wait_ready);
            cpu_read_switch(wait_ready, pattern[2]);
            cpu_write(8'h01, wait_ready);
            cpu_read_switch(wait_ready, pattern[3]);
        end
    endtask

    logic [3:0] stalled_pattern;
    logic [3:0] impatient_pattern;

    initial begin
        repeat (10) @(posedge clk50);
        reset <= 1'b0;
        repeat (10) @(posedge clk50);

        read_switch_pattern(1'b1, stalled_pattern);
        if (stalled_pattern !== 4'b0111) begin
            errors = errors + 1;
            $display("FAIL: stalled CPU assembled %04b, expected CGA 80 pattern 0111",
                     stalled_pattern);
        end

        repeat (40) @(posedge clk50);

        read_switch_pattern(1'b0, impatient_pattern);
        if (impatient_pattern !== 4'b0111) begin
            errors = errors + 1;
            $display("FAIL: CPU that does not honour access_ready assembled %04b, expected 0111",
                     impatient_pattern);
        end

        if (errors == 0)
            $display("PASS: ISA switch sense preserves IBM CGA 80 pattern 0111 with and without ready stalls");
        else
            $display("FAIL: %0d real-path switch checks failed", errors);
        $finish;
    end

    initial begin
        #3_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
