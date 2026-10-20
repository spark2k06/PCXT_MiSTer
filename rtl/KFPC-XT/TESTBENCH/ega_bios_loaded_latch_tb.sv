`timescale 1ns/1ps

module ega_bios_loaded_latch_tb;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic sdram_initialized = 1'b0;
    logic download_active = 1'b0;
    logic write_complete = 1'b0;
    logic loaded;
    wire  write_protect;
    wire [1:0] video_switches;

    always #5 clock = ~clock;

    ega_bios_loaded_latch dut (
        .clock             (clock),
        .reset             (reset),
        .sdram_initialized (sdram_initialized),
        .download_active   (download_active),
        .write_complete    (write_complete),
        .loaded            (loaded),
        .write_protect     (write_protect),
        .video_switches    (video_switches)
    );

    task automatic check_loaded(input logic expected_value, input string context_text);
        begin
            #1;
            if (loaded !== expected_value)
                $fatal(1, "%s: loaded=%b, expected %b", context_text, loaded, expected_value);
            if (write_protect !== expected_value)
                $fatal(1, "%s: write_protect=%b, expected %b",
                       context_text, write_protect, expected_value);
            if (video_switches !== (expected_value ? 2'b00 : 2'b10))
                $fatal(1, "%s: video_switches=%b", context_text, video_switches);
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset <= 1'b0;
        sdram_initialized <= 1'b1;
        @(posedge clock);
        check_loaded(1'b0, "reset state");

        // Start an EGA ROM download and complete its first 16-bit word.
        download_active <= 1'b1;
        @(posedge clock);
        check_loaded(1'b0, "new download invalidates the previous image");

        write_complete <= 1'b1;
        @(posedge clock);
        write_complete <= 1'b0;
        check_loaded(1'b1, "a completed word marks the EGA ROM present");

        // The real loader revisits its input state between every word.  With
        // download_active still high, those gaps must not clear the flag.
        repeat (6) begin
            @(posedge clock);
            check_loaded(1'b1, "inter-word gap preserves presence");
        end

        write_complete <= 1'b1;
        @(posedge clock);
        write_complete <= 1'b0;
        check_loaded(1'b1, "later words preserve presence");

        download_active <= 1'b0;
        repeat (3) @(posedge clock);
        check_loaded(1'b1, "end-of-file preserves presence");

        // A new upload invalidates the old image exactly once.  An aborted
        // upload remains absent; a later successful upload becomes persistent.
        download_active <= 1'b1;
        @(posedge clock);
        check_loaded(1'b0, "next file invalidates old image once");
        repeat (3) @(posedge clock);
        check_loaded(1'b0, "empty inter-word gaps do not fabricate presence");
        download_active <= 1'b0;
        @(posedge clock);
        check_loaded(1'b0, "aborted file remains absent");

        download_active <= 1'b1;
        @(posedge clock);
        write_complete <= 1'b1;
        @(posedge clock);
        write_complete <= 1'b0;
        download_active <= 1'b0;
        @(posedge clock);
        check_loaded(1'b1, "successful replacement remains present");

        sdram_initialized <= 1'b0;
        @(posedge clock);
        check_loaded(1'b0, "SDRAM reinitialization clears presence");

        $display("PASS: EGA BIOS presence survives loader word gaps and end-of-file");
        $finish;
    end

endmodule
