`timescale 1ns/1ps

// The mixer's job that matters is not volume, it is being recognised.
//
// Three separate detection routines in real software read this register file
// back and refuse to use the card if the answer is wrong, and each fails in a
// way that looks like something else entirely:
//
//   - SBPDIG.ADV read-modify-writes the mic volume at 0Ah. Ultima Underworld
//     and Dune II use it to decide a Sound Blaster Pro is present at all.
//   - The MASI driver v2.90 in Epic Pinball and Jazz Jackrabbit writes F3h to
//     the master volume at 22h and enables stereo only if F3h reads back. The
//     reserved bits 0 and 4 must therefore return 1, not 0 - a mixer that
//     zeroes them plays in mono and looks like it is working.
//   - Register 0Eh bit 1 is what arms interleaved stereo in the DSP, so it has
//     to reach the DSP and read back.
//
// This bench drives the mixer through soundblaster's real bus decode rather
// than poking the register file directly, so a decode mistake at 2x4h/2x5h
// fails here too.
module sb_mixer_tb;

    localparam TB_CYCLE = 200;

    logic        clock = 1'b0;
    logic        reset = 1'b1;
    logic [15:0] address = 16'h0000;
    logic [7:0]  data_bus = 8'h00;
    logic        io_read_n = 1'b1;
    logic        io_write_n = 1'b1;

    wire         read_select;
    wire [7:0]   data_bus_out;
    wire         irq, dma_request;
    wire [15:0]  sample_l, sample_r;

    always #(TB_CYCLE / 2) clock = ~clock;

    soundblaster u_sb (
        .clock              (clock),
        .reset              (reset),
        .cpu_ce_negedge     (1'b1),
        .clk_rate           (28'd5_000_000),
        .address            (address),
        .internal_data_bus  (data_bus),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),
        .address_enable_n   (1'b0),
        .enable             (1'b1),
        .read_select        (read_select),
        .data_bus_out       (data_bus_out),
        .dma_acknowledge    (1'b0),
        .dma_request        (dma_request),
        .irq                (irq),
        .fm_l               (16'sd0),
        .fm_r               (16'sd0),
        .sample_l           (sample_l),
        .sample_r           (sample_r)
    );

    // A bus cycle that holds the address across the trailing edge of the
    // command, the way the 8282 latches do on the real machine.
    task automatic bus_write(input [15:0] a, input [7:0] d);
        begin
            @(negedge clock); address = a; data_bus = d; io_write_n = 1'b0;
            repeat (3) @(negedge clock);
            io_write_n = 1'b1;
            repeat (3) @(negedge clock);
        end
    endtask

    task automatic bus_read(input [15:0] a);
        begin
            @(negedge clock); address = a; io_read_n = 1'b0;
            repeat (3) @(negedge clock);
            io_read_n = 1'b1;
            repeat (3) @(negedge clock);
        end
    endtask

    // Mixer access is always an index write then a data access.
    task automatic mixer_write(input [7:0] index, input [7:0] d);
        begin
            bus_write(16'h0224, index);
            bus_write(16'h0225, d);
        end
    endtask

    task automatic mixer_read(input [7:0] index);
        begin
            bus_write(16'h0224, index);
            bus_read(16'h0225);
        end
    endtask

    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clock);
        reset = 1'b0;
        repeat (5) @(posedge clock);

        // ------------------------------------------------ MASI stereo detect
        // The exact sequence the driver runs, and the exact value it needs.
        mixer_write(8'h22, 8'hF3);
        mixer_read(8'h22);
        check(data_bus_out == 8'hF3,
              $sformatf("master volume read back %02h, expected F3 - MASI would drop to mono",
                        data_bus_out));

        // The reserved bits must be set even when the volume is not.
        mixer_write(8'h22, 8'h00);
        mixer_read(8'h22);
        check(data_bus_out == 8'h11,
              $sformatf("master volume at zero read back %02h, expected 11 (reserved bits set)",
                        data_bus_out));

        // ------------------------------------------------- SBPDIG mic detect
        // Every value the 2-bit field can hold has to survive the round trip
        // through the 5-bit internal form.
        for (int m = 0; m < 4; m++) begin
            automatic logic [7:0] w = {5'b00000, m[1:0], 1'b0};
            mixer_write(8'h0A, w);
            mixer_read(8'h0A);
            check(data_bus_out == w,
                  $sformatf("mic volume wrote %02h, read back %02h", w, data_bus_out));
        end

        // ------------------------------------------------------ voice and FM
        mixer_write(8'h04, 8'hF3);
        mixer_read(8'h04);
        check(data_bus_out == 8'hF3,
              $sformatf("voice volume read back %02h, expected F3", data_bus_out));

        mixer_write(8'h26, 8'h33);
        mixer_read(8'h26);
        check(data_bus_out == 8'h33,
              $sformatf("FM volume read back %02h, expected 33", data_bus_out));

        // ----------------------------------------------------- stereo switch
        mixer_write(8'h0E, 8'h02);               // bit 1 = stereo on
        check(u_sb.sbp_stereo,
              "mixer register 0Eh bit 1 did not reach the DSP as sbp_stereo");
        mixer_read(8'h0E);
        check(data_bus_out[1],
              $sformatf("stereo bit did not read back set, got %02h", data_bus_out));

        mixer_write(8'h0E, 8'h00);
        check(!u_sb.sbp_stereo, "stereo did not clear");

        // ------------------------------------------------------------- reset
        // A write to register 00h returns everything to defaults, whatever the
        // data byte says.
        mixer_write(8'h22, 8'h00);
        mixer_write(8'h0E, 8'h02);
        mixer_write(8'h00, 8'hFF);
        check(!u_sb.sbp_stereo, "mixer reset did not clear stereo");
        mixer_read(8'h22);
        check(data_bus_out != 8'h11,
              "mixer reset did not restore a non-zero master volume");

        // -------------------------------------------- 2x4h must not be claimed
        // The index port is write-only on the real card. Claiming it for reads
        // would shadow whatever else answers there.
        @(negedge clock); address = 16'h0224; io_read_n = 1'b0;
        repeat (2) @(negedge clock);
        check(!read_select, "2x4h was claimed for a read; it is write-only");
        io_read_n = 1'b1;
        address = 16'h0000;

        if (errors == 0) $display("PASS: mixer registers read back as the detection routines expect");
        else             $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(TB_CYCLE * 20000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
