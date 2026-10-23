`timescale 1ns/1ps

// PCjr cold boot: the warm-start flag reads as zero after a reset until the
// BIOS writes it, and only on a PCjr.
module pcjr_cold_boot_tb;
    logic clock = 1'b0;
    logic reset = 1'b1;
    logic pcjr = 1'b1;
    logic [19:0] address = 20'h00000;
    logic select = 1'b1;
    logic memory_write_n = 1'b1;
    wire  override;
    integer errors = 0;

    always #5 clock = ~clock;

    pcjr_cold_boot dut (.*);

    task automatic check(input logic expect_v, input string what);
        begin
            #1;
            if (override !== expect_v) begin
                $display("FAIL: %s: override %b, expected %b", what, override, expect_v);
                errors++;
            end
        end
    endtask

    task automatic write_at(input logic [19:0] a, input logic sel);
        begin
            @(negedge clock);
            address = a; select = sel; memory_write_n = 1'b0;
            @(negedge clock);
            memory_write_n = 1'b1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clock);
        reset = 1'b0;
        address = 20'h00472; check(1'b1, "flag low byte after reset");
        address = 20'h00473; check(1'b1, "flag high byte after reset");
        address = 20'h00474; check(1'b0, "next address");
        address = 20'h00471; check(1'b0, "previous address");
        address = 20'hFFFF0; check(1'b0, "BIOS area");
        write_at(20'h00100, 1'b1);
        address = 20'h00472; check(1'b1, "an unrelated write does not clear it");
        write_at(20'h00472, 1'b0);
        address = 20'h00472; check(1'b1, "a write the RAM does not take does not clear it");
        write_at(20'h00472, 1'b1);
        address = 20'h00472; check(1'b0, "after the BIOS writes the flag");
        address = 20'h00473; check(1'b0, "after the write, high byte");
        // Another reset starts a cold boot again
        reset = 1'b1; #2; reset = 1'b0;
        address = 20'h00472; check(1'b1, "cold again after a reset");
        write_at(20'h00473, 1'b1);
        address = 20'h00473; check(1'b0, "a write of the high byte clears it");
        // Not a PCjr: never
        reset = 1'b1; #2; reset = 1'b0;
        pcjr = 1'b0;
        address = 20'h00472; check(1'b0, "not a PCjr");
        if (errors == 0) $display("PASS pcjr_cold_boot_tb");
        else $display("FAIL pcjr_cold_boot_tb: %0d errors", errors);
        $finish;
    end
endmodule
