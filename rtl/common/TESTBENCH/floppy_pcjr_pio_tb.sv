`timescale 1ns/1ps

// floppy.v in pcjr_mode (F6): the diskette adapter of the IBM PCjr, ports F0h-F5h
// by programmed I/O. A session as the BIOS does it: reset through the DOR,
// specify, recalibrate, sense interrupt, read a sector byte by byte through F5h
// (polling F4h), write a sector, and the watchdog interrupt (DOR bit 6 falling
// edge, 1 s later IRQ6 if DOR bit 5 is set).
//
//   iverilog -g2012 -o pio.vvp TESTBENCH/floppy_pcjr_pio_tb.sv floppy.v simple_fifo.v
module floppy_pcjr_pio_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n = 1'b0;
    reg  [2:0] io_address = 3'd0;
    reg        io_read = 1'b0, io_write = 1'b0;
    reg  [7:0] io_writedata = 8'h00;
    reg  [3:0] init_address = 4'd0;
    reg        init_write = 1'b0;
    reg [15:0] init_writedata = 16'd0;
    reg        host_write = 1'b0, host_read = 1'b0;
    reg [15:0] host_data = 16'd0;
    wire [3:0]  mgmt_address   = (host_write | host_read) ? 4'hF : init_address;
    wire        mgmt_write     = init_write | host_write;
    wire [15:0] mgmt_writedata = host_write ? host_data : init_writedata;
    wire        mgmt_read      = host_read;
    wire [15:0] mgmt_readdata;

    wire        dma_req, irq;
    wire  [7:0] io_readdata;
    wire  [1:0] request;

    // 1 kHz of watchdog ticks need clock_rate cycles per second: use a small rate
    // so that the 1000 ticks of a second take 1000 * (rate / 1000) = rate cycles
    localparam [27:0] RATE = 28'd200_000;

    floppy dut (
        .clk(clk), .rst_n(rst_n), .pcjr_mode(1'b1),
        .dma_req(dma_req), .dma_ack(1'b0), .dma_tc(1'b0), .dma_readdata(8'h00),
        .dma_writedata(), .irq(irq),
        .io_address(io_address), .io_read(io_read), .io_readdata(io_readdata),
        .io_write(io_write), .io_writedata(io_writedata), .fdd0_inserted(),
        .mgmt_address(mgmt_address), .mgmt_fddn(1'b0), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .mgmt_read(mgmt_read),
        .mgmt_readdata(mgmt_readdata), .wp(2'b00), .clock_rate(RATE), .request(request)
    );

    integer errors = 0;
    task check(input bit ok, input string what);
        if (!ok) begin errors++; $display("ERROR: %s", what); end
    endtask

    task mgmt(input [3:0] a, input [15:0] d);
        @(posedge clk); init_address <= a; init_writedata <= d; init_write <= 1'b1;
        @(posedge clk); init_write <= 1'b0;
    endtask

    task io_wr(input [2:0] a, input [7:0] d);
        @(posedge clk); io_address <= a; io_writedata <= d; io_write <= 1'b1;
        @(posedge clk); io_write <= 1'b0;
        repeat (6) @(posedge clk);
    endtask

    logic [7:0] rd;
    task io_rd(input [2:0] a);
        // Like the chipset: the address is stable before the strobe, and the
        // data is taken one clock after it (io_readdata is registered)
        @(posedge clk); io_address <= a;
        repeat (3) @(posedge clk);
        io_read <= 1'b1;
        @(posedge clk); io_read <= 1'b0;
        @(posedge clk); rd = io_readdata;
        repeat (4) @(posedge clk);
    endtask

    // The host fills the buffer when asked for a sector (the FIFO is a byte wide:
    // byte w of the sector is w mod 256) and drains it when there is one to write
    integer w;
    integer host_reads = 0, host_writes = 0;
    always @(posedge clk) begin
        if (request[0] && !host_write) begin
            for (w = 0; w < 512; w = w + 1) begin
                host_write <= 1'b1; host_data <= 16'(w & 255);
                @(posedge clk);
            end
            host_write <= 1'b0; host_writes++;
            repeat (8) @(posedge clk);
        end else if (request[1] && !host_read) begin
            for (w = 0; w < 512; w = w + 1) begin
                host_read <= 1'b1;
                @(posedge clk);
            end
            host_read <= 1'b0; host_reads++;
            repeat (8) @(posedge clk);
        end
    end

    // Wait for F4h = want (mask), at most limit polls
    task wait_status(input [7:0] mask, input [7:0] want, input integer limit, input string what);
        integer n;
        n = 0;
        do begin io_rd(3'd4); n++; end while (((rd & mask) != want) && n < limit);
        check((rd & mask) == want, $sformatf("%s: F4h = %02h (wanted %02h/%02h)", what, rd, want, mask));
    endtask

    task cmd_byte(input [7:0] b, input string what);
        wait_status(8'hC0, 8'h80, 400, what);
        io_wr(3'd5, b);
    endtask

    logic [7:0] sector [0:511];
    integer i;
    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        mgmt(4'd2, 16'd40); mgmt(4'd3, 16'd9); mgmt(4'd4, 16'd360); mgmt(4'd5, 16'd1);
        mgmt(4'd1, 16'd0);  mgmt(4'd0, 16'd1);

        // F0h/F1h/F3h read as the adapter does
        io_rd(3'd3); check(rd == 8'h20, "F3h reads 20h");
        io_wr(3'd2, 8'h80); io_wr(3'd2, 8'h01);          // reset, then motor on
        io_rd(3'd1); check(rd[5:4] == 2'b11, $sformatf("F1h with the motor on: %02h", rd));

        // Specify, recalibrate, sense interrupt
        cmd_byte(8'h03, "specify"); cmd_byte(8'hDF, "specify 1"); cmd_byte(8'h02, "specify 2");
        cmd_byte(8'h07, "recalibrate"); cmd_byte(8'h00, "recalibrate drive");
        repeat (200000) @(posedge clk);
        cmd_byte(8'h08, "sense interrupt");
        wait_status(8'hD0, 8'hD0, 400, "sense result 1"); io_rd(3'd5);
        // Right after the reset the first answer is the one of the ready line (C0h)
        check(rd == 8'hC0 || rd[5] === 1'b1, $sformatf("sense interrupt ST0 = %02h", rd));
        wait_status(8'hD0, 8'hD0, 400, "sense result 2"); io_rd(3'd5);
        check(rd == 8'h00, $sformatf("sense interrupt PCN = %02h", rd));

        // Read data: cylinder 0, head 0, sector 1, 512 bytes, EOT 1
        cmd_byte(8'h46, "read"); cmd_byte(8'h00, "r1"); cmd_byte(8'h00, "r2"); cmd_byte(8'h00, "r3");
        cmd_byte(8'h01, "r4"); cmd_byte(8'h02, "r5"); cmd_byte(8'h01, "r6"); cmd_byte(8'h1B, "r7");
        cmd_byte(8'hFF, "r8");
        for (i = 0; i < 512; i++) begin
            wait_status(8'hF0, 8'hF0, 20000, "read data ready");
            io_rd(3'd5);
            sector[i] = rd;
        end
        begin
            int bad = 0;
            for (i = 0; i < 512; i++)
                if (sector[i] !== 8'(i & 255)) bad++;
            check(bad == 0, $sformatf("%0d of 512 bytes read wrong (first %02h %02h %02h %02h)",
                                      bad, sector[0], sector[1], sector[2], sector[3]));
        end
        for (i = 0; i < 7; i++) begin
            wait_status(8'hD0, 8'hD0, 20000, "read result");
            io_rd(3'd5);
            if (i == 0) check(rd[7:6] == 2'b00, $sformatf("read ST0 = %02h", rd));
        end
        check(host_writes == 1, "the host supplied the sector once");

        // Write data: sector 2, 512 bytes
        cmd_byte(8'h45, "write"); cmd_byte(8'h00, "w1"); cmd_byte(8'h00, "w2"); cmd_byte(8'h00, "w3");
        cmd_byte(8'h02, "w4"); cmd_byte(8'h02, "w5"); cmd_byte(8'h02, "w6"); cmd_byte(8'h1B, "w7");
        cmd_byte(8'hFF, "w8");
        for (i = 0; i < 512; i++) begin
            wait_status(8'hF0, 8'hB0, 20000, "write ready");
            io_wr(3'd5, 8'(i));
        end
        for (i = 0; i < 7; i++) begin
            wait_status(8'hD0, 8'hD0, 40000, "write result");
            io_rd(3'd5);
            if (i == 0) check(rd[7:6] == 2'b00, $sformatf("write ST0 = %02h", rd));
        end
        check(host_reads == 1, $sformatf("the host took the written sector once (%0d)", host_reads));

        // Watchdog: DOR bit 6 high then low arms it; one second later IRQ6 if DOR bit 5
        io_wr(3'd2, 8'h61);
        check(irq === 1'b0, "no interrupt before the watchdog");
        io_wr(3'd2, 8'h21);
        repeat (RATE / 2) @(posedge clk);
        check(irq === 1'b0, "no interrupt half a second into the watchdog");
        repeat (RATE) @(posedge clk);
        check(irq === 1'b1, "watchdog interrupt after one second");
        io_wr(3'd2, 8'h80); io_wr(3'd2, 8'h01);
        check(irq === 1'b0, "the controller reset clears the interrupt");

        check(dma_req === 1'b0, "pcjr_mode never requests DMA");
        $display("floppy_pcjr_pio_tb: %0d errors", errors);
        if (errors != 0) $fatal(1, "FAIL");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $fatal(1, "FAIL");
    end
endmodule
