//============================================================================
//
//  The EU adder must be bit-for-bit what the ripple was.
//
//  mcl86_adder replaced a per-bit ripple carry inside mcl86_eu_core with a
//  single '+', so that Quartus would map it onto the ALM carry chain instead of
//  building sixteen chained LUT expressions. That chain was the critical path of
//  the entire core and the reason clk_100 closed at 88 MHz against its 100 MHz
//  constraint.
//
//  The change is only safe if the two are the same function, and "the same
//  function" here means more than the sum agreeing. The EU takes five separate
//  carries out of this adder and turns them into architectural flags:
//
//      carry[4]              BCD auxiliary carry  -> AF
//      carry[8]              byte carry out       -> CF for byte ops
//      carry[16]             word carry out       -> CF for word ops
//      carry[8]  ^ carry[7]  signed overflow, byte -> OF
//      carry[16] ^ carry[15] signed overflow, word -> OF
//
//  A sum that is right while carry[7] is wrong would corrupt OF on byte
//  arithmetic and nothing else - the kind of fault that runs a whole BIOS POST
//  and then breaks one conditional branch in one game. So this bench compares
//  all seventeen carries, not just the ones with names.
//
//  The reference model below is the original expression, copied unchanged from
//  mcl86_eu_core.sv before the replacement. It is deliberately the textbook
//  ripple and deliberately not written any more cleverly than it was: its job is
//  to be obviously the old behaviour, not to be good RTL.
//
//  Coverage is every carry-propagation pattern that exists rather than a sample
//  of them. b = ~a makes every bit propagate, so a single carry crosses the full
//  width; b = 1 and b = 0xFFFF walk a carry up from the bottom for every possible
//  run length; b = 0x5555 and 0xAAAA alternate generate and kill; a = b doubles.
//  Each of those is swept against all 65536 values of a, which pins the boundary
//  bits 3/4, 7/8 and 15/16 that the flags are taken from.
//
//============================================================================

`timescale 1ns/1ps

// The original per-bit ripple, verbatim from mcl86_eu_core.sv.
module mcl86_adder_ref
    (
        input  wire [15:0] a,
        input  wire [15:0] b,
        output wire [15:0] sum,
        output wire [16:0] carry
    );

    assign carry[0] = 1'b0;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_adder
            assign sum[i]     =  a[i] ^ b[i] ^ carry[i];
            assign carry[i+1] = (a[i] & b[i]) | (a[i] & carry[i]) | (b[i] & carry[i]);
        end
    endgenerate

endmodule


module mcl86_adder_tb;

    reg  [15:0] a, b;

    wire [15:0] dut_sum,  ref_sum;
    wire [16:0] dut_carry, ref_carry;

    mcl86_adder     dut (.a(a), .b(b), .sum(dut_sum), .carry(dut_carry));
    mcl86_adder_ref u_ref (.a(a), .b(b), .sum(ref_sum), .carry(ref_carry));

    integer mismatches   = 0;
    integer vectors      = 0;
    integer sum_bad      = 0;
    integer carry_bad    = 0;
    integer flagbit_bad  = 0;

    // Only the first few failures are printed; a broken index would otherwise
    // produce hundreds of thousands of identical lines.
    localparam integer MAX_REPORTS = 12;

    task automatic check;
        begin
            vectors = vectors + 1;
            #1;
            if ((dut_sum !== ref_sum) || (dut_carry !== ref_carry)) begin
                mismatches = mismatches + 1;
                if (dut_sum   !== ref_sum)   sum_bad   = sum_bad   + 1;
                if (dut_carry !== ref_carry) carry_bad = carry_bad + 1;
                // Did it land on a bit the flags are actually taken from?
                if ((dut_carry[4]  !== ref_carry[4])  ||
                    (dut_carry[7]  !== ref_carry[7])  ||
                    (dut_carry[8]  !== ref_carry[8])  ||
                    (dut_carry[15] !== ref_carry[15]) ||
                    (dut_carry[16] !== ref_carry[16]))
                    flagbit_bad = flagbit_bad + 1;

                if (mismatches <= MAX_REPORTS)
                    $display("  FAIL  a=%04h b=%04h  sum %04h/%04h  carry %05h/%05h",
                             a, b, dut_sum, ref_sum, dut_carry, ref_carry);
            end
        end
    endtask

    // Sweep every value of a against one fixed relationship for b.
    task automatic sweep(input integer mode, input [255:0] label);
        integer k;
        begin
            for (k = 0; k < 65536; k = k + 1) begin
                a = k[15:0];
                case (mode)
                    0: b = 16'h0000;
                    1: b = 16'h0001;
                    2: b = 16'hFFFF;
                    3: b = 16'h5555;
                    4: b = 16'hAAAA;
                    5: b = ~a;          // every bit propagates
                    6: b = a;           // doubling
                    7: b = 16'h8000;
                    8: b = 16'h7FFF;
                    default: b = 16'h0000;
                endcase
                check;
            end
            $display("  swept %0s", label);
        end
    endtask

    integer n;

    initial begin
        $display("");
        $display("=== the EU adder must be bit-for-bit what the ripple was ===");
        $display("");

        // Labels are held in a 256-bit vector, so 31 characters is the ceiling
        // and anything longer comes out with its front chopped off.
        sweep(0, "b = 0000  zero");
        sweep(1, "b = 0001  carry from bit 0");
        sweep(2, "b = FFFF  every run length");
        sweep(3, "b = 5555  generate/kill");
        sweep(4, "b = AAAA  opposite phase");
        sweep(5, "b = ~a    full propagate");
        sweep(6, "b = a     doubling");
        sweep(7, "b = 8000  pins carry 15/16");
        sweep(8, "b = 7FFF  all but top bit");

        for (n = 0; n < 200000; n = n + 1) begin
            a = $random;
            b = $random;
            check;
        end
        $display("  200000 random pairs");

        $display("");
        $display("%0d vectors, %0d mismatches", vectors, mismatches);
        if (mismatches != 0) begin
            $display("  of which sum differed:            %0d", sum_bad);
            $display("  of which a carry differed:        %0d", carry_bad);
            $display("  of which a FLAG carry differed:   %0d", flagbit_bad);
            $display("RESULT: FAIL");
        end
        else begin
            $display("sum and all 17 carries identical on every vector");
            $display("RESULT: PASS");
        end
        $display("");
        $finish;
    end

endmodule
