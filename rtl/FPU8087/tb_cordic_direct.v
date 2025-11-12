`timescale 1ns / 1ps

//=====================================================================
// Direct CORDIC Wrapper Testbench
//
// Tests FPU_CORDIC_Wrapper directly to isolate conversion and
// iteration issues without microcode layer.
//=====================================================================

module tb_cordic_direct;

    // Clock and reset
    reg clk;
    reg reset;

    // Control signals
    reg enable;
    reg mode;

    // Inputs
    reg [79:0] angle_in;
    reg [79:0] x_in;
    reg [79:0] y_in;

    // Outputs
    wire [79:0] sin_out;
    wire [79:0] cos_out;
    wire [79:0] atan_out;
    wire [79:0] magnitude_out;
    wire done;
    wire error;

    // Instantiate CORDIC wrapper
    FPU_CORDIC_Wrapper cordic (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .mode(mode),
        .angle_in(angle_in),
        .x_in(x_in),
        .y_in(y_in),
        .sin_out(sin_out),
        .cos_out(cos_out),
        .atan_out(atan_out),
        .magnitude_out(magnitude_out),
        .done(done),
        .error(error)
    );

    // Clock generation: 10ns period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Helper task: Convert FP80 to real for display
    task fp80_to_real;
        input [79:0] fp80;
        output real result;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        integer exp_unbiased;
        real mant_real;
        begin
            sign = fp80[79];
            exponent = fp80[78:64];
            mantissa = fp80[63:0];

            if (exponent == 15'h7FFF) begin
                result = (mantissa == 64'd0) ? (sign ? -1.0e308 : 1.0e308) : 0.0;
            end else if (exponent == 15'd0 && mantissa == 64'd0) begin
                result = 0.0;
            end else begin
                exp_unbiased = exponent - 16383;
                mant_real = mantissa / (2.0 ** 63.0);
                result = mant_real * (2.0 ** exp_unbiased);
                if (sign) result = -result;
            end
        end
    endtask

    // Test execution task
    task test_cordic_rotation;
        input [79:0] angle;
        input real expected_sin;
        input real expected_cos;
        input [80*8-1:0] test_name;
        real sin_val, cos_val;
        integer timeout;
        begin
            $display("\n========================================");
            $display("Test: %s", test_name);
            $display("Angle: 0x%020X", angle);

            // Start CORDIC in rotation mode
            angle_in = angle;
            mode = 1'b0;  // Rotation mode
            enable = 1;
            @(posedge clk);
            enable = 0;

            // Wait for completion with timeout
            timeout = 0;
            while (!done && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 100000) begin
                $display("✗ TIMEOUT after %0d cycles", timeout);
            end else begin
                $display("Completed in %0d cycles", timeout);
                $display("sin_out: 0x%020X", sin_out);
                $display("cos_out: 0x%020X", cos_out);

                fp80_to_real(sin_out, sin_val);
                fp80_to_real(cos_out, cos_val);

                $display("Expected: sin=%f, cos=%f", expected_sin, expected_cos);
                $display("Got:      sin=%f, cos=%f", sin_val, cos_val);
            end
        end
    endtask

    // Main test sequence
    initial begin
        $display("\n========================================");
        $display("Direct CORDIC Wrapper Tests");
        $display("========================================");

        // Initialize
        reset = 1;
        enable = 0;
        mode = 0;
        angle_in = 0;
        x_in = 0;
        y_in = 0;

        // Reset sequence
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(5) @(posedge clk);

        // Test 1: sin(0) = 0, cos(0) = 1
        test_cordic_rotation(80'h0000_0000000000000000, 0.0, 1.0, "sin(0), cos(0)");

        // Test 2: Small angle - π/6 ≈ 0.5236 rad (within CORDIC range)
        // sin(π/6) = 0.5, cos(π/6) ≈ 0.866
        test_cordic_rotation(80'h3FFE860A91C16B9B3000, 0.5, 0.866025404, "sin(π/6), cos(π/6)");

        // Test 3: π/4 ≈ 0.7854 rad (close to CORDIC limit)
        // sin(π/4) = cos(π/4) ≈ 0.707
        test_cordic_rotation(80'h3FFEC90FDAA22168C000, 0.707106781, 0.707106781, "sin(π/4), cos(π/4)");

        // Test 4: Very small angle - 0.1 rad
        // sin(0.1) ≈ 0.0998, cos(0.1) ≈ 0.995
        test_cordic_rotation(80'h3FFB_CCCCCCCCCCCCCD00, 0.0998334166, 0.9950041653, "sin(0.1), cos(0.1)");

        $display("\n========================================");
        $display("Test Complete");
        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000000;  // 10ms timeout
        $display("\n*** ERROR: Global timeout reached ***\n");
        $finish;
    end

endmodule
