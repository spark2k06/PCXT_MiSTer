`timescale 1ns/1ps

// Instrument validation for the Sound Blaster DMA glue.
//
// Before any Sound Blaster code exists, this bench establishes what a real
// channel-1 DMA cycle looks like in THIS core, using the real BUS_ARBITER and
// the real KF8237 rather than a hand-written model of them. Everything the
// glue will later rely on is asserted here:
//
//   - DACK1 falls out of the arbiter at all (nothing else in the core uses
//     channel 1, so this path has never been exercised)
//   - the address presented during the cycle is the programmed one, which
//     means the page register the arbiter picks for channel 1 is the right
//     one. Bus_Arbiter.sv has no explicit case for channel 1 and lands in the
//     else branch on dma_page_register[3]; on a real XT channel 1's page
//     register is port 83h, which decodes to index 3, so the fallthrough is
//     correct. This bench is what proves that rather than assuming it.
//   - MEMR and IOW are both asserted, and the memory byte is on
//     internal_data_bus while IOW is low - that is the only window in which a
//     peripheral can capture a DMA byte here, because the KF8237 hands nothing
//     to the device directly.
//
// Icarus cannot elaborate the KF8237 (it rejects the whole-array assignments
// in the priority encoder), so this one runs under Verilator.
module sb_dma_cycle_tb;

    localparam TB_CYCLE = 200;

    logic         clock = 1'b0;
    logic         reset = 1'b1;

    // Every clock is both CPU edges, matching Chipset_tb.
    wire          cpu_ce_posedge = 1'b1;
    wire          cpu_ce_negedge = 1'b1;

    logic [19:0]  cpu_address = '0;
    logic [7:0]   cpu_data_bus = '0;
    logic [2:0]   processor_status = 3'b111;
    logic         processor_lock_n = 1'b1;
    logic         dma_ready = 1'b1;
    logic         dma_chip_select_n = 1'b1;
    logic         dma_page_chip_select_n = 1'b1;
    logic [19:0]  address_ext = '0;
    logic [7:0]   data_bus_ext;
    logic         io_read_n_ext = 1'b1;
    logic         io_write_n_ext = 1'b1;
    logic         memory_read_n_ext = 1'b1;
    logic         memory_write_n_ext = 1'b1;
    logic         ext_access_request = 1'b0;
    logic [3:0]   dma_request = 4'b0000;

    wire          processor_transmit_or_receive_n;
    wire          dma_wait_n;
    wire          interrupt_acknowledge_n;
    wire [19:0]   address;
    wire          address_direction;
    wire [7:0]    internal_data_bus;
    wire          data_bus_direction;
    wire          address_latch_enable;
    wire          io_read_n;
    wire          io_read_n_direction;
    wire          io_write_n;
    wire          io_write_n_direction;
    wire          memory_read_n;
    wire          memory_read_n_direction;
    wire          memory_write_n;
    wire          memory_write_n_direction;
    wire          no_command_state;
    wire [3:0]    dma_acknowledge_n;
    wire          address_enable_n;
    wire          terminal_count_n;

    always #(TB_CYCLE / 2) clock = ~clock;

    BUS_ARBITER dut (.*);

    // ---------------------------------------------------------------- memory
    // Stands in for RAM.sv, which drives data_bus_ext on a memory read. The
    // pattern is address-derived so a byte landing in the wrong place is
    // visible rather than plausible.
    function automatic [7:0] mem_byte(input [19:0] a);
        mem_byte = a[7:0] ^ 8'h5A;
    endfunction

    always_comb begin
        if (~memory_read_n) data_bus_ext = mem_byte(address);
        else                data_bus_ext = 8'hFF;
    end

    // ------------------------------------------------------------- CPU cycles
    task automatic io_write(input [19:0] addr, input [7:0] data);
        begin
            cpu_address      = addr;
            cpu_data_bus     = data;
            processor_status = 3'b010;
            #(TB_CYCLE * 4);
            processor_status = 3'b111;
            #(TB_CYCLE * 1);
            cpu_address      = 20'h00000;
            cpu_data_bus     = 8'h00;
            #(TB_CYCLE * 1);
        end
    endtask

    // The 8237 answers on 00h..0Fh, which is what dma_chip_select_n gates.
    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    // ------------------------------------------------------------------ checks
    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    localparam [15:0] XFER_ADDR = 16'h1234;
    localparam [3:0]  XFER_PAGE = 4'h5;

    // What the cycle actually showed.
    logic        saw_dack1     = 1'b0;
    logic        saw_memr      = 1'b0;
    logic        saw_iow       = 1'b0;
    logic [19:0] dack_address  = '0;
    logic [7:0]  dack_data     = '0;

    // Capture the first channel-1 cycle. The data is sampled while IOW is low,
    // which is the window the glue will latch in.
    always @(posedge clock) begin
        if (~dma_acknowledge_n[1]) begin
            saw_dack1 <= 1'b1;
            if (~memory_read_n) begin
                saw_memr     <= 1'b1;
                dack_address <= address;
            end
            if (~io_write_n) begin
                saw_iow   <= 1'b1;
                dack_data <= internal_data_bus;
            end
        end
    end

    initial begin
        repeat (10) @(posedge clock);
        reset = 1'b0;
        #(TB_CYCLE * 4);

        // Page register for channel 1 lives at port 83h -> index 3.
        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hD, 8'h00);                 // master clear
        #(TB_CYCLE * 2);

        dma_write(4'hB, 8'h49);                 // mode: single, inc, read (mem->dev), ch1
        dma_write(4'hC, 8'h00);                 // clear byte pointer
        dma_write(4'h2, XFER_ADDR[7:0]);        // base address low
        dma_write(4'h2, XFER_ADDR[15:8]);       // base address high
        dma_write(4'h3, 8'h0F);                 // count low  (16 transfers)
        dma_write(4'h3, 8'h00);                 // count high
        dma_write(4'hA, 8'h01);                 // unmask channel 1

        #(TB_CYCLE * 4);

        // Ask for one transfer.
        dma_request[1] = 1'b1;
        #(TB_CYCLE * 40);
        dma_request[1] = 1'b0;
        #(TB_CYCLE * 10);

        check(saw_dack1, "DACK1 never asserted - channel 1 does not reach the bus");
        check(saw_memr,  "MEMR never asserted during the channel-1 cycle");
        check(saw_iow,   "IOW never asserted during the channel-1 cycle");
        check(dack_address == {XFER_PAGE, XFER_ADDR},
              $sformatf("DMA address was %05h, expected %05h (page register mismatch)",
                        dack_address, {XFER_PAGE, XFER_ADDR}));
        check(dack_data == mem_byte({XFER_PAGE, XFER_ADDR}),
              $sformatf("bus carried %02h during IOW, expected %02h",
                        dack_data, mem_byte({XFER_PAGE, XFER_ADDR})));

        if (errors == 0) $display("PASS: channel-1 DMA cycle presents %05h -> %02h with MEMR+IOW",
                                  dack_address, dack_data);
        else             $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    // Watchdog.
    initial begin
        #(TB_CYCLE * 4000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
