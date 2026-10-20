`timescale 1ns/1ps

// Does FM actually come out the other side?
//
// The OPL2 no longer reaches the top-level mix directly. Peripherals silences
// that path whenever the Sound Blaster is built and routes the FM through this
// module instead, so the card's mixer register 26h can set its level the way a
// real one does. That makes this module the only thing standing between the
// OPL2 and the speakers, in every configuration - including plain Adlib on
// 388h with the card switched off.
//
// So there are two paths to hold down, and a silent one is a dead FM:
//
//   enable low  - straight passthrough, no gain stage in the way at all
//   enable high - through the shared-multiplier gain stage, attenuated by the
//                 MIDI and master volumes
//
// The numbers here are deliberately not exact. What matters is that a loud FM
// input produces a loud output of the right sign and the right rough
// magnitude; asserting the exact product would just restate the gain table.
module sb_fm_path_tb;

    localparam TB_CYCLE = 200;

    logic        clock = 1'b0;
    logic        reset = 1'b1;
    logic [15:0] fm    = 16'sd0;
    logic        enable = 1'b0;

    wire         read_select, irq, dma_request;
    wire  [7:0]  data_bus_out;
    wire  [15:0] sample_l, sample_r;

    always #(TB_CYCLE / 2) clock = ~clock;

    soundblaster u_sb (
        .clock              (clock),
        .reset              (reset),
        .cpu_ce_negedge     (1'b1),
        .clk_rate           (28'd5_000_000),
        .address            (16'h0000),
        .internal_data_bus  (8'h00),
        .io_read_n          (1'b1),
        .io_write_n         (1'b1),
        .address_enable_n   (1'b0),
        .enable             (enable),
        .read_select        (read_select),
        .data_bus_out       (data_bus_out),
        .dma_acknowledge    (1'b0),
        .dma_request        (dma_request),
        .irq                (irq),
        .fm_l               (fm),
        .fm_r               (fm),
        .sample_l           (sample_l),
        .sample_r           (sample_r)
    );

    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    function automatic int abs16(input logic signed [15:0] v);
        abs16 = (v < 0) ? -int'(v) : int'(v);
    endfunction

    // Long enough for the gain stage to walk all six channels several times
    // and for the master's feedback of the summed mix to settle.
    task automatic settle();
        begin
            repeat (60) @(posedge clock);
        end
    endtask

    initial begin
        repeat (5) @(posedge clock);
        reset = 1'b0;
        repeat (5) @(posedge clock);

        // ---------------------------------------------------- card switched off
        // Adlib at 388h with no Sound Blaster selected. Nothing may touch the
        // signal here - not even the mixer's default volumes.
        enable = 1'b0;
        fm     = 16'sh4000;
        settle();
        check(sample_l == 16'sh4000,
              $sformatf("passthrough left was %04h, expected 4000", sample_l));
        check(sample_r == 16'sh4000,
              $sformatf("passthrough right was %04h, expected 4000", sample_r));

        fm = -16'sh4000;
        settle();
        check(sample_l == -16'sh4000,
              $sformatf("negative passthrough was %04h, expected C000", sample_l));

        // ------------------------------------------------------- card switched on
        // Now through the gain stage. With the mixer at its reset defaults the
        // MIDI and master volumes are one step down each, so the result should
        // land somewhere near half scale - clearly audible, definitely not
        // silence and not full scale either.
        enable = 1'b0;
        fm     = 16'sd0;
        settle();
        enable = 1'b1;
        fm     = 16'sh4000;
        settle();

        check(sample_l != 16'sd0,
              "FM is silent with the card enabled - the gain stage swallowed it");
        check(!sample_l[15],
              $sformatf("FM changed sign through the gain stage: %04h", sample_l));
        check(abs16(sample_l) > 16'sd4000,
              $sformatf("FM came out far too quiet: %04h from 4000", sample_l));
        check(abs16(sample_l) <= 16'sh4000,
              $sformatf("FM came out louder than it went in: %04h from 4000", sample_l));

        check(sample_r == sample_l,
              $sformatf("channels disagree on a mono FM input: l=%04h r=%04h",
                        sample_l, sample_r));

        // The output must hold steady rather than flicker as the shared
        // multiplier walks its channels - a value that changes every few
        // clocks with a constant input is the crackle you would hear.
        begin
            automatic logic [15:0] first = sample_l;
            automatic int          changes = 0;
            repeat (40) begin
                @(posedge clock);
                if (sample_l !== first) changes++;
            end
            check(changes == 0,
                  $sformatf("output moved %0d times on a constant input (%04h -> %04h)",
                            changes, first, sample_l));
        end

        // A negative input must stay negative.
        fm = -16'sh4000;
        settle();
        check(sample_l[15],
              $sformatf("negative FM came out positive through the gain stage: %04h",
                        sample_l));

        if (errors == 0) $display("PASS: FM reaches the output on both paths");
        else             $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(TB_CYCLE * 20000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
