`timescale 1ns/1ps

// Focused regression for the HOLD/HLDA hand-off.  The real 8237 is replaced
// by a pin-compatible observer so this test checks only Bus_Arbiter's edge
// sequencing.  A request made while the CPU is passive must be visible to the
// DMA controller on the first following CPU falling edge.
module Bus_Arbiter_Hold_tb;
    logic         clock = 1'b0;
    logic         reset = 1'b1;
    logic         cpu_ce_posedge = 1'b0;
    logic         cpu_ce_negedge = 1'b0;
    logic [19:0]  cpu_address = '0;
    logic [7:0]   cpu_data_bus = '0;
    logic [2:0]   processor_status = 3'b111;
    logic         processor_lock_n = 1'b1;
    logic         dma_ready = 1'b1;
    logic         dma_chip_select_n = 1'b1;
    logic         dma_page_chip_select_n = 1'b1;
    logic [19:0]  address_ext = '0;
    logic [7:0]   data_bus_ext = '0;
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

    always #5 clock = ~clock;

    BUS_ARBITER dut (.*);

    task automatic cpu_edge(input logic positive_edge);
        begin
            @(negedge clock);
            cpu_ce_posedge = positive_edge;
            cpu_ce_negedge = ~positive_edge;
            @(posedge clock);
            #1;
            cpu_ce_posedge = 1'b0;
            cpu_ce_negedge = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clock);
        reset = 1'b0;

        // Assert DREQ just after a falling edge, then present the CPU rising
        // edge on which the arbiter confirms that the passive bus is free.
        @(negedge clock);
        dma_request[0] = 1'b1;
        cpu_edge(1'b1);
        cpu_edge(1'b0);

        if (!dut.u_KF8237.saw_ack_on_first_negedge) begin
            $error("8237 did not observe HOLD acknowledge on the first falling edge");
            $fatal(1);
        end

        $display("PASS: HOLD acknowledge reached the 8237 without an extra CPU clock");
        $finish;
    end
endmodule

// Minimal 8288 pin stub used only by this unit test.
module KF8288 (
    input  logic clock, cpu_ce_posedge, cpu_ce_negedge, reset,
    input  logic address_enable_n, command_enable, io_bus_mode,
    input  logic [2:0] processor_status,
    output logic enable_io_command, advanced_io_write_command_n,
    output logic io_read_command_n, interrupt_acknowledge_n,
    output logic enable_memory_command, advanced_memory_write_command_n,
    output logic memory_read_command_n, direction_transmit_or_receive_n,
    output logic data_enable, address_latch_enable
);
    always_comb begin
        enable_io_command = 1'b0;
        advanced_io_write_command_n = 1'b1;
        io_read_command_n = 1'b1;
        interrupt_acknowledge_n = 1'b1;
        enable_memory_command = 1'b0;
        advanced_memory_write_command_n = 1'b1;
        memory_read_command_n = 1'b1;
        direction_transmit_or_receive_n = 1'b1;
        data_enable = 1'b0;
        address_latch_enable = 1'b0;
    end
endmodule

// Minimal 8237 pin stub.  DREQ directly raises HRQ and the observer samples
// HLDA exactly as the real controller does on cpu_ce_negedge.
module KF8237 (
    input  logic clock, cpu_ce_posedge, cpu_ce_negedge, reset,
    input  logic chip_select_n, ready, hold_acknowledge,
    input  logic [3:0] dma_request,
    input  logic [7:0] data_bus_in,
    output logic [7:0] data_bus_out,
    input  logic io_read_n_in,
    output logic io_read_n_out, io_read_n_io,
    input  logic io_write_n_in,
    output logic io_write_n_out, io_write_n_io,
    input  logic end_of_process_n_in,
    output logic end_of_process_n_out,
    input  logic [3:0] address_in,
    output logic [15:0] address_out,
    output logic output_highst_address, hold_request,
    output logic [3:0] dma_acknowledge,
    output logic address_enable, address_strobe,
    output logic memory_read_n, memory_write_n
);
    logic saw_ack_on_first_negedge = 1'b0;
    logic first_negedge_pending = 1'b0;

    assign hold_request = |dma_request;

    always_ff @(posedge clock) begin
        if (reset) begin
            first_negedge_pending <= 1'b0;
            saw_ack_on_first_negedge <= 1'b0;
        end else begin
            if (cpu_ce_posedge && hold_request)
                first_negedge_pending <= 1'b1;
            if (cpu_ce_negedge && first_negedge_pending) begin
                saw_ack_on_first_negedge <= hold_acknowledge;
                first_negedge_pending <= 1'b0;
            end
        end
    end

    always_comb begin
        data_bus_out = '0;
        io_read_n_out = 1'b1;
        io_read_n_io = 1'b1;
        io_write_n_out = 1'b1;
        io_write_n_io = 1'b1;
        end_of_process_n_out = 1'b1;
        address_out = '0;
        output_highst_address = 1'b0;
        dma_acknowledge = 4'b1111;
        address_enable = 1'b0;
        address_strobe = 1'b0;
        memory_read_n = 1'b1;
        memory_write_n = 1'b1;
    end
endmodule
