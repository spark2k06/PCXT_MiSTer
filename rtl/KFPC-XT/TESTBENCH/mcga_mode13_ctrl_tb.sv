`timescale 1ns / 1ps

module mcga_mode13_ctrl_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg mcga_enabled = 1'b0;
    reg mode13_set = 1'b0;
    reg mode13_clear = 1'b0;
    wire mcga_mode13_active;

    integer errors = 0;

    mcga_mode13_ctrl dut (
        .clk(clk),
        .reset(reset),
        .mcga_enabled(mcga_enabled),
        .mode13_set(mode13_set),
        .mode13_clear(mode13_clear),
        .mcga_mode13_active(mcga_mode13_active)
    );

    always #5 clk = ~clk;

    task automatic expect1;
        input [127:0] name;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected %0b got %0b", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task automatic pulse_set;
        begin
            @(negedge clk);
            mode13_set = 1'b1;
            @(negedge clk);
            mode13_set = 1'b0;
        end
    endtask

    task automatic pulse_clear;
        begin
            @(negedge clk);
            mode13_clear = 1'b1;
            @(negedge clk);
            mode13_clear = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 1'b0;
        repeat (1) @(negedge clk);
        expect1("reset clears mode13", mcga_mode13_active, 1'b0);

        pulse_set();
        expect1("disabled gate blocks set", mcga_mode13_active, 1'b0);

        mcga_enabled = 1'b1;
        pulse_set();
        expect1("enabled gate allows set", mcga_mode13_active, 1'b1);

        pulse_clear();
        expect1("clear exits mode13", mcga_mode13_active, 1'b0);

        pulse_set();
        expect1("enabled gate allows set after clear", mcga_mode13_active, 1'b1);

        mcga_enabled = 1'b0;
        repeat (1) @(negedge clk);
        expect1("dropping gate clears active mode13", mcga_mode13_active, 1'b0);

        mcga_enabled = 1'b1;
        pulse_set();
        expect1("enabled gate allows final set", mcga_mode13_active, 1'b1);

        reset = 1'b1;
        repeat (1) @(negedge clk);
        expect1("reset clears active mode13", mcga_mode13_active, 1'b0);

        if (errors == 0)
            $display("PASS mcga_mode13_ctrl_tb");
        else
            $display("FAIL mcga_mode13_ctrl_tb: %0d errors", errors);
        $finish;
    end
endmodule
