`timescale 1ns/1ps

// Command E2h, the DMA identification, writing into memory.
//
// Every other transfer this card does runs memory to device: the 8237 asserts
// MEMR and IOW and we take the byte off the bus. E2h runs the other way. The
// 8237 asserts IOR at the card and MEMW at the memory, and the card is the one
// that has to drive the data. Nothing else in this design does that, which is
// how it came to be left unconnected and why no playback test could notice.
//
// CT-VOICE.DRV notices. It does not use E2h as a diagnostic - it stores the
// pointer to its own play routine encrypted in its dispatch table and uses the
// DSP to decrypt it. The table entry for function 6 holds FE9Ch on disk. The
// driver feeds those two bytes back through E2h and lets the DMA write the
// answers over the top of them, and the answers are the real entry point.
//
// The algorithm is an accumulator starting at AAh and an XOR key starting at
// 96h, rotated right two bits per use:
//
//     AAh + (9Ch ^ 96h) = B4h
//     B4h + (FEh ^ A5h) = 0Fh        -> 0FB4h, a valid offset in the driver
//
// So this is card authentication, and getting it wrong is not subtle: with the
// bus undriven the 8237 latches FFh twice, function 6 becomes a call to offset
// FFFFh, and the first digitised sound a game plays jumps into open memory.
//
// This replays exactly what the driver's init does - programme channel 1 for a
// device-to-memory transfer of two bytes, then E2h 9Ch and E2h FEh - and reads
// the memory back. Real BUS_ARBITER, real KF8237, so the cycles are the ones
// the hardware runs. Icarus cannot elaborate that controller; this is Verilator.
module sb_dma_id_tb;

    localparam TB_CYCLE  = 200;
    localparam CLK_RATE  = 28'd5_000_000;

    logic         clock = 1'b0;
    logic         reset = 1'b1;

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
    wire  [3:0]   dma_request;

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

    wire          sb_dma_request;
    assign dma_request = {2'b00, sb_dma_request, 1'b0};

    BUS_ARBITER u_arbiter (.*);

    // ---------------------------------------------------------------- memory
    // Writable this time, because the whole point is what lands in it.
    logic [7:0] dmem [0:65535];

    always_ff @(posedge clock) begin
        if (~memory_write_n) dmem[address[15:0]] <= internal_data_bus;
    end

    always_comb begin
        if (~memory_read_n)                     data_bus_ext = dmem[address[15:0]];
        else if (~io_read_n && sb_read_select)  data_bus_ext = sb_data_bus_out;
        else                                    data_bus_ext = 8'hFF;
    end

    // ---------------------------------------------------------- Sound Blaster
    wire          sb_read_select;
    wire  [7:0]   sb_data_bus_out;
    wire          sb_irq;
    wire  [15:0]  sample_l, sample_r;

    soundblaster u_sb (
        .clock              (clock),
        .reset              (reset),
        .cpu_ce_negedge     (cpu_ce_negedge),
        .clk_rate           (CLK_RATE),
        .address            (address[15:0]),
        .internal_data_bus  (internal_data_bus),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),
        .address_enable_n   (address_enable_n),
        .enable             (1'b1),
        .read_select        (sb_read_select),
        .data_bus_out       (sb_data_bus_out),
        .dma_acknowledge    (~dma_acknowledge_n[1]),
        .dma_request        (sb_dma_request),
        .irq                (sb_irq),
        .fm_l               (16'd0),
        .fm_r               (16'd0),
        .sample_l           (sample_l),
        .sample_r           (sample_r)
    );

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
            #(TB_CYCLE * 2);
        end
    endtask

    logic [7:0] last_read;

    task automatic io_read(input [19:0] addr);
        begin
            cpu_address      = addr;
            processor_status = 3'b001;
            #(TB_CYCLE * 4);
            last_read        = sb_data_bus_out;
            processor_status = 3'b111;
            #(TB_CYCLE * 1);
            cpu_address      = 20'h00000;
            #(TB_CYCLE * 2);
        end
    endtask

    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    task automatic dsp_write(input [7:0] data);
        begin
            io_write(20'h0022C, data);
        end
    endtask

    // ------------------------------------------------------------- the test
    // The address the driver uses is CS:0095h, its own dispatch table. Any
    // address does here; what matters is that two bytes land and what they are.
    localparam [15:0] XFER_ADDR = 16'h0095;
    localparam [3:0]  XFER_PAGE = 4'h0;

    // The two bytes the table holds on disk, fed back in as the driver does.
    localparam [7:0] SEED_LO = 8'h9C;
    localparam [7:0] SEED_HI = 8'hFE;

    // And what a real card answers with.
    localparam [7:0] WANT_LO = 8'hB4;
    localparam [7:0] WANT_HI = 8'h0F;

    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    initial begin
        for (int i = 0; i < 65536; i++) dmem[i] = 8'h00;
        // Salt the target so a transfer that never happens cannot be mistaken
        // for one that wrote the right answer.
        dmem[XFER_ADDR]     = 8'h11;
        dmem[XFER_ADDR + 1] = 8'h22;

        repeat (10) @(posedge clock);
        reset = 1'b0;
        #(TB_CYCLE * 4);

        // ------------------------------------------------ reset the DSP first
        // The seeds only decrypt correctly from the cold values, AAh and 96h,
        // which a reset restores. The driver resets before it identifies.
        io_write(20'h00226, 8'h01);
        #(TB_CYCLE * 4);
        io_write(20'h00226, 8'h00);
        #(TB_CYCLE * 8);
        io_read(20'h0022A);
        check(last_read == 8'hAA,
              $sformatf("reset acknowledge was %02h, expected AA", last_read));

        // -------------------------- channel 1, device to memory, two bytes
        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hD, 8'h00);                 // master clear
        #(TB_CYCLE * 2);
        dma_write(4'hB, 8'h45);                 // single, increment, dev->mem, ch1
        dma_write(4'hC, 8'h00);                 // clear byte pointer
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, 8'h01);                 // count 1, so two transfers
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);                 // unmask channel 1

        // ------------------------------------- E2h twice, as the driver does
        dsp_write(8'hE2);
        dsp_write(SEED_LO);
        #(TB_CYCLE * 200);
        dsp_write(8'hE2);
        dsp_write(SEED_HI);
        #(TB_CYCLE * 200);

        // ------------------------------------------------------------ checks
        check(dmem[XFER_ADDR] != 8'h11,
              "nothing was written at all - the card never drove the bus");
        check(dmem[XFER_ADDR] != 8'hFF && dmem[XFER_ADDR+1] != 8'hFF,
              "FFh landed in memory, which is an undriven bus, not an answer");
        check(dmem[XFER_ADDR] == WANT_LO,
              $sformatf("first byte was %02h, expected %02h", dmem[XFER_ADDR], WANT_LO));
        check(dmem[XFER_ADDR + 1] == WANT_HI,
              $sformatf("second byte was %02h, expected %02h", dmem[XFER_ADDR+1], WANT_HI));

        if (errors == 0)
            $display("PASS: E2h decrypted %02h%02h into %02h%02h, the driver's real entry point",
                     SEED_HI, SEED_LO, dmem[XFER_ADDR+1], dmem[XFER_ADDR]);
        else
            $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(TB_CYCLE * 20000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
