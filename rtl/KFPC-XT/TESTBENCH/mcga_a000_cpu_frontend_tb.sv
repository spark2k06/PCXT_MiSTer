`timescale 1ns / 1ps

module mcga_a000_cpu_frontend_tb;

    reg         clock = 1'b0;
    reg         clk_video = 1'b0;
    reg         reset = 1'b1;
    reg         active = 1'b0;
    reg  [19:0] address = 20'h00000;
    reg  [7:0]  cpu_din = 8'h00;
    reg         iorq = 1'b0;
    reg         address_enable_n = 1'b0;
    reg         memory_read_n = 1'b1;
    reg         memory_write_n = 1'b1;
    wire        a000_select;
    wire        cpu_cycle;
    wire [7:0]  cpu_dout;
    wire        cpu_ready;
    wire [7:0]  video_pixel;
    wire        video_data_valid;

    integer failures = 0;

    mcga_a000_cpu_frontend dut (
        .clock              (clock),
        .reset              (reset),
        .clk_video          (clk_video),
        .active             (active),
        .address            (address),
        .cpu_din            (cpu_din),
        .iorq               (iorq),
        .address_enable_n   (address_enable_n),
        .memory_read_n      (memory_read_n),
        .memory_write_n     (memory_write_n),
        .a000_select        (a000_select),
        .cpu_cycle          (cpu_cycle),
        .cpu_dout           (cpu_dout),
        .cpu_ready          (cpu_ready),
        .video_addr         (16'h0000),
        .video_read_en      (1'b0),
        .video_pixel        (video_pixel),
        .video_data_valid   (video_data_valid)
    );

    always #5 clock = ~clock;
    always #7 clk_video = ~clk_video;

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task idle;
        begin
            memory_read_n = 1'b1;
            memory_write_n = 1'b1;
            @(posedge clock);
        end
    endtask

    task write_mem;
        input [19:0] addr;
        input [7:0] data;
        begin
            address = addr;
            cpu_din = data;
            memory_write_n = 1'b0;
            @(posedge clock);
            #1;
            check(cpu_ready, "write should be ready after one clock");
            idle();
        end
    endtask

    task read_mem;
        input [19:0] addr;
        input [7:0] expected;
        begin
            address = addr;
            memory_read_n = 1'b0;
            @(posedge clock);
            #1;
            check(cpu_ready, "read should be ready after one clock");
            check(cpu_dout == expected, "packed readback mismatch");
            idle();
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        idle();

        address = 20'hA1234;
        memory_write_n = 1'b0;
        @(posedge clock);
        #1;
        check(!a000_select, "inactive mode must not select A000");
        check(!cpu_cycle, "inactive mode must not issue packed framebuffer cycle");
        idle();

        active = 1'b1;
        write_mem(20'hA0000, 8'h12);
        write_mem(20'hA1234, 8'h5A);
        write_mem(20'hAFFFF, 8'hE7);
        read_mem(20'hA0000, 8'h12);
        read_mem(20'hA1234, 8'h5A);
        read_mem(20'hAFFFF, 8'hE7);

        address = 20'hB0000;
        memory_read_n = 1'b0;
        @(posedge clock);
        #1;
        check(!a000_select, "active mode must ignore non-A000 memory");
        check(!cpu_cycle, "non-A000 memory must not issue packed framebuffer cycle");
        idle();

        iorq = 1'b1;
        address = 20'hA2222;
        memory_read_n = 1'b0;
        @(posedge clock);
        #1;
        check(!a000_select, "I/O cycle must not select A000 memory");
        check(!cpu_cycle, "I/O cycle must not issue packed framebuffer cycle");
        idle();

        if (failures == 0) begin
            $display("PASS mcga_a000_cpu_frontend_tb");
            $finish;
        end

        $display("FAIL mcga_a000_cpu_frontend_tb failures=%0d", failures);
        $finish;
    end

endmodule
