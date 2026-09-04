// Focused test for the legacy 80286 FLAGS compatibility profile.
`timescale 1ns/1ps
`default_nettype none

module mcl86_fake286_flags_tb;
    logic core_clock = 1'b0;
    always #5 core_clock = ~core_clock;

    logic fake286_flags = 1'b0;
    wire [15:0] eu_biu_dataout;

    mcl86_eu_core dut (
        .CORE_CLK_INT(core_clock), .RESET_INT(1'b0), .TEST_N_INT(1'b1),
        .FAKE286_FLAGS(fake286_flags),
        .EU_BIU_COMMAND(), .EU_BIU_DATAOUT(eu_biu_dataout), .EU_REGISTER_R3(),
        .EU_PREFIX_LOCK(), .EU_FLAG_I(), .BIU_DONE(1'b0),
        .BIU_CLK_COUNTER_ZERO(1'b1), .BIU_NMI_CAUGHT(1'b0),
        .BIU_NMI_DEBOUNCE(), .BIU_INTR(1'b0), .PFQ_TOP_BYTE(8'h00),
        .PFQ_EMPTY(1'b1), .PFQ_ADDR_OUT(16'h0000),
        .BIU_REGISTER_ES(16'h0000), .BIU_REGISTER_SS(16'h0000),
        .BIU_REGISTER_CS(16'h0000), .BIU_REGISTER_DS(16'h0000),
        .BIU_REGISTER_RM(16'h0000), .BIU_REGISTER_REG(16'h0000),
        .BIU_RETURN_DATA(16'h0000)
    );

    integer errors = 0;
    task automatic check(input string tag, input logic [15:0] expected);
        begin
            if (dut.eu_alu_out !== expected) begin
                errors = errors + 1;
                $display("FAIL: %s PUSHF data=%04h expected=%04h fake=%b pushf=%b ucode=%08h", tag,
                         dut.eu_alu_out, expected, fake286_flags,
                         dut.eu_pushf_serialize, dut.eu_rom_data);
                $display("      type=%h dst=%h op0=%h op1=%h imm=%04h", dut.eu_opcode_type,
                         dut.eu_opcode_dst_sel, dut.eu_opcode_op0_sel,
                         dut.eu_opcode_op1_sel, dut.eu_opcode_immediate);
            end
        end
    endtask

    initial begin
        // 5F8FF002 is the ROM's PUSHF FLAGS-to-BIU microword.  Force it so
        // this stays a precise unit test, independent of instruction fetch.
        force dut.eu_flags = 16'hFABC;
        force dut.eu_rom_data = 32'h5F8FF002;
        #1 check("native profile preserves 8086 reserved bits", 16'hFABE);

        fake286_flags = 1'b1;
        #1 check("Fake 286 clears reserved FLAGS[15:12] for PUSHF", 16'h0ABE);

        // The same FLAGS read must remain private microcode state outside PUSHF.
        force dut.eu_rom_data = 32'h588F0002;
        #1 check("Fake 286 does not mask FLAGS for unrelated microcode", 16'hFABE);

        if (errors == 0)
            $display("RESULT: PASS (Fake 286 FLAGS only affects PUSHF serialisation)");
        else
            $display("RESULT: FAIL (%0d checks)", errors);
        $finish;
    end
endmodule

`default_nettype wire
