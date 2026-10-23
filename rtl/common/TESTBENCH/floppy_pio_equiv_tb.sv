`timescale 1ns/1ps

// floppy.v with pcjr_mode = 0 must be the DMA controller the PCXT and the Tandy
// have always had. Drives the committed floppy.v and a copy of the previous one
// (floppy_ref, made by the script that runs this bench) with the same random
// register traffic, DMA handshakes, media settings and resets, and compares
// every output on every clock.
//
//   git show <rev>:rtl/common/floppy.v | sed 's/^module floppy/module floppy_ref/' > floppy_ref.v
//   iverilog -g2012 -o eq.vvp TESTBENCH/floppy_pio_equiv_tb.sv floppy.v floppy_ref.v && vvp eq.vvp
module floppy_pio_equiv_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n = 1'b0;
    reg        dma_ack = 1'b0, dma_tc = 1'b0;
    reg  [7:0] dma_readdata = 8'h00;
    reg  [2:0] io_address = 3'd0;
    reg        io_read = 1'b0, io_write = 1'b0;
    reg  [7:0] io_writedata = 8'h00;
    reg  [3:0] init_address = 4'd0;
    reg        init_write = 1'b0;
    reg [15:0] init_writedata = 16'd0;
    // The host (HPS) side of the sector buffer: fills the FIFO when the
    // controller asks for a sector and empties it when it has one to write
    reg        host_write = 1'b0, host_read = 1'b0;
    reg [15:0] host_data = 16'd0;
    wire [3:0]  mgmt_address   = (host_write | host_read) ? 4'hF : init_address;
    wire        mgmt_write     = init_write | host_write;
    wire [15:0] mgmt_writedata = host_write ? host_data : init_writedata;
    wire        mgmt_read      = host_read;
    reg  [1:0] wp = 2'b00;

    wire        n_dma_req, r_dma_req, n_irq, r_irq, n_ins, r_ins;
    wire  [7:0] n_dma_wd, r_dma_wd, n_rd, r_rd;
    wire [15:0] n_mgmt, r_mgmt;
    wire  [1:0] n_req, r_req;

    floppy dut (
        .clk(clk), .rst_n(rst_n), .pcjr_mode(1'b0),
        .dma_req(n_dma_req), .dma_ack(dma_ack), .dma_tc(dma_tc),
        .dma_readdata(dma_readdata), .dma_writedata(n_dma_wd), .irq(n_irq),
        .io_address(io_address), .io_read(io_read), .io_readdata(n_rd),
        .io_write(io_write), .io_writedata(io_writedata), .fdd0_inserted(n_ins),
        .mgmt_address(mgmt_address), .mgmt_fddn(1'b0), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .mgmt_read(mgmt_read), .mgmt_readdata(n_mgmt),
        .wp(wp), .clock_rate(28'd50_000_000), .request(n_req)
    );
    floppy_ref ref0 (
        .clk(clk), .rst_n(rst_n),
        .dma_req(r_dma_req), .dma_ack(dma_ack), .dma_tc(dma_tc),
        .dma_readdata(dma_readdata), .dma_writedata(r_dma_wd), .irq(r_irq),
        .io_address(io_address), .io_read(io_read), .io_readdata(r_rd),
        .io_write(io_write), .io_writedata(io_writedata), .fdd0_inserted(r_ins),
        .mgmt_address(mgmt_address), .mgmt_fddn(1'b0), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .mgmt_read(mgmt_read), .mgmt_readdata(r_mgmt),
        .wp(wp), .clock_rate(28'd50_000_000), .request(r_req)
    );

    integer errors = 0, cycles = 0, seed = 1;
    integer n_irqs = 0, n_dma = 0, n_req_seen = 0;
    wire [7:0] unused_ref_dma = r_dma_wd;
    always @(posedge clk) begin
        cycles++;
        if ({n_dma_req, n_irq, n_ins, n_dma_wd, n_rd, n_mgmt, n_req} !==
            {r_dma_req, r_irq, r_ins, r_dma_wd, r_rd, r_mgmt, r_req}) begin
            errors++;
            if (errors <= 10)
                $display("MISMATCH at %0d: dma_req %b/%b irq %b/%b rd %02h/%02h mgmt %04h/%04h req %b/%b",
                         cycles, n_dma_req, r_dma_req, n_irq, r_irq, n_rd, r_rd, n_mgmt, r_mgmt, n_req, r_req);
        end
        if (n_irq) n_irqs++;
        if (n_dma_req) n_dma++;
        if (n_req != 0) n_req_seen++;
    end

    task mgmt(input [3:0] a, input [15:0] d);
        @(posedge clk); init_address <= a; init_writedata <= d; init_write <= 1'b1;
        @(posedge clk); init_write <= 1'b0;
    endtask

    integer w;
    always @(posedge clk) begin
        if (n_req[0] && !host_write) begin
            for (w = 0; w < 256; w = w + 1) begin
                host_write <= 1'b1; host_data <= {8'(w), 8'(w * 7 + 3)};
                @(posedge clk);
            end
            host_write <= 1'b0;
            repeat (8) @(posedge clk);
        end else if (n_req[1] && !host_read) begin
            for (w = 0; w < 256; w = w + 1) begin
                host_read <= 1'b1;
                @(posedge clk);
            end
            host_read <= 1'b0;
            repeat (8) @(posedge clk);
        end
    end

    // The DMA controller: a short handshake for every request, the terminal
    // count now and then
    integer dma_n = 0;
    always @(posedge clk) begin
        if (n_dma_req && !dma_ack) begin
            dma_n <= dma_n + 1;
            dma_ack <= 1'b1;
            dma_tc <= (dma_n % 512) == 511;
            dma_readdata <= $urandom_range(0, 255);
            repeat (3) @(posedge clk);
            dma_ack <= 1'b0; dma_tc <= 1'b0;
            repeat (3) @(posedge clk);
        end
    end

    task io_wr(input [2:0] a, input [7:0] d);
        @(posedge clk); io_address <= a; io_writedata <= d; io_write <= 1'b1;
        @(posedge clk); io_write <= 1'b0;
        repeat ($urandom_range(2, 40)) @(posedge clk);
    endtask

    task io_rd(input [2:0] a);
        @(posedge clk); io_address <= a; io_read <= 1'b1;
        @(posedge clk); io_read <= 1'b0;
        repeat ($urandom_range(2, 20)) @(posedge clk);
    endtask

    // Command bytes that the controller knows, and noise
    function automatic [7:0] cmd_byte();
        case ($urandom_range(0, 14))
            0: return 8'h03; 1: return 8'h04; 2: return 8'h07; 3: return 8'h08;
            4: return 8'h0F; 5: return 8'h4A; 6: return 8'h46; 7: return 8'h66;
            8: return 8'h45; 9: return 8'h4D; 10: return 8'h06; 11: return 8'h05;
            default: return $urandom_range(0, 255);
        endcase
    endfunction

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        mgmt(4'd2, 16'd80);      // cylinders
        mgmt(4'd3, 16'd9);       // sectors per track
        mgmt(4'd4, 16'd720);     // total sectors
        mgmt(4'd5, 16'd2);       // heads
        mgmt(4'd1, 16'd0);       // not write-protected
        mgmt(4'd0, 16'd1);       // media present
        // A proper session first: DOR, specify, recalibrate, sense interrupt, read and
        // write a sector, format a track
        io_wr(3'd2, 8'h1C);
        io_wr(3'd5, 8'h03); io_wr(3'd5, 8'hDF); io_wr(3'd5, 8'h02);
        io_wr(3'd5, 8'h07); io_wr(3'd5, 8'h00);
        repeat (400) @(posedge clk);
        io_wr(3'd5, 8'h08); repeat (20) io_rd(3'd5);
        io_wr(3'd5, 8'h46); io_wr(3'd5, 8'h00); io_wr(3'd5, 8'h00); io_wr(3'd5, 8'h00);
        io_wr(3'd5, 8'h01); io_wr(3'd5, 8'h02); io_wr(3'd5, 8'h09); io_wr(3'd5, 8'h1B); io_wr(3'd5, 8'hFF);
        repeat (6000) @(posedge clk);
        repeat (12) io_rd(3'd5);
        io_wr(3'd5, 8'h45); io_wr(3'd5, 8'h00); io_wr(3'd5, 8'h00); io_wr(3'd5, 8'h00);
        io_wr(3'd5, 8'h02); io_wr(3'd5, 8'h02); io_wr(3'd5, 8'h09); io_wr(3'd5, 8'h1B); io_wr(3'd5, 8'hFF);
        repeat (6000) @(posedge clk);
        repeat (12) io_rd(3'd5);
        io_wr(3'd5, 8'h4D); io_wr(3'd5, 8'h00); io_wr(3'd5, 8'h02); io_wr(3'd5, 8'h09);
        io_wr(3'd5, 8'h1B); io_wr(3'd5, 8'hE5);
        repeat (6000) @(posedge clk);
        repeat (12) io_rd(3'd5);
        for (int it = 0; it < 6000; it++) begin
            case ($urandom_range(0, 9))
                0, 1, 2: io_wr(3'd5, cmd_byte());                 // FIFO / command
                3: io_wr(3'd2, $urandom_range(0, 255));           // DOR
                4: io_wr(3'd4, $urandom_range(0, 255));           // data rate / config
                5, 6: io_rd(3'd4);                                // main status
                7: io_rd(3'd5);                                   // FIFO read
                8: io_rd(3'd5);
                default: begin
                    wp <= $urandom_range(0, 3);
                    if ($urandom_range(0, 40) == 0) begin         // a reset in the middle
                        rst_n <= 1'b0; repeat (3) @(posedge clk); rst_n <= 1'b1;
                    end
                    io_rd(3'd0 + $urandom_range(0, 7));
                end
            endcase
        end
        $display("floppy_pio_equiv_tb: %0d cycles, %0d mismatches (irq %0d, dma_req %0d, request %0d cycles seen)",
                 cycles, errors, n_irqs, n_dma, n_req_seen);
        if (errors != 0) $fatal(1, "FAIL");
        $finish;
    end
endmodule
