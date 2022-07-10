//
// KF8237_Priority_Encoder
// Priority Encoder And Rotating Priority Logic
//
// Written by Kitune-san
//
`include "KF8237_Common_Package.svh"

module KF8237_Priority_Encoder (
    input   logic           clock,
    input   logic           cpu_clock_posedge,
    input   logic           cpu_clock_negedge,
    input   logic           reset,

    // Internal Bus
    input   logic   [7:0]   internal_data_bus,
    // -- write
    input   logic           write_command_register,
    input   logic           write_request_register,
    input   logic           set_or_reset_mask_register,
    input   logic           write_mask_register,
    // -- software command
    input   logic           master_clear,
    input   logic           clear_mask_register,

    // Internal signals
    input   logic   [1:0]   dma_rotate,
    input   logic   [3:0]   edge_request,
    output  logic   [3:0]   dma_request_state,
    output  logic   [3:0]   encoded_dma,
    input   logic           end_of_process_internal,
    input   logic   [3:0]   dma_acknowledge_internal,

    // External signals
    input   logic   [3:0]   dma_request
);
    import KF8237_Common_Package::rotate_right;
    import KF8237_Common_Package::rotate_left;
    import KF8237_Common_Package::resolv_priority;

    logic   [1:0]   bit_select[4] = '{ 2'b00, 2'b01, 2'b10, 2'b11 };
    logic           controller_disable;
    logic           rotating_priority;
    logic           dreq_sense_active_low;
    logic   [3:0]   mask_register;
    logic   [3:0]   request_register;
    logic   [3:0]   dma_request_ff;
    logic   [3:0]   dma_request_lock;


    //
    // Command Register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            controller_disable <= 1'b0;
        else if (master_clear)
            controller_disable <= 1'b0;
        else if (write_command_register)
            controller_disable <= internal_data_bus[2];
        else
            controller_disable <= controller_disable;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            rotating_priority <= 1'b0;
        else if (master_clear)
            rotating_priority <= 1'b0;
        else if (write_command_register)
            rotating_priority <= internal_data_bus[4];
        else
            rotating_priority <= rotating_priority;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dreq_sense_active_low <= 1'b0;
        else if (master_clear)
            dreq_sense_active_low <= 1'b0;
        else if (write_command_register)
            dreq_sense_active_low <= internal_data_bus[6];
        else
            dreq_sense_active_low <= dreq_sense_active_low;
    end

    //
    // Mask Register
    //
    genvar mask_bit_i;
    generate
    for (mask_bit_i = 0; mask_bit_i < 4; mask_bit_i = mask_bit_i + 1) begin : MASK_REGISTER
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                mask_register[mask_bit_i] <= 1'b1;
            else if ((master_clear) || (clear_mask_register))
                mask_register[mask_bit_i] <= 1'b1;
            else if ((set_or_reset_mask_register) && (internal_data_bus[1:0] == bit_select[mask_bit_i]))
                mask_register[mask_bit_i] <= internal_data_bus[2];
            else if (write_mask_register)
                mask_register[mask_bit_i] <= internal_data_bus[mask_bit_i];
            else
                mask_register[mask_bit_i] <= mask_register[mask_bit_i];
        end
    end
    endgenerate

    //
    // Request Register
    //
    genvar req_reg_bit_i;
    generate
    for (req_reg_bit_i = 0; req_reg_bit_i < 4; req_reg_bit_i = req_reg_bit_i + 1) begin : REQUEST_REGISTER
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                request_register[req_reg_bit_i] <= 1'b0;
            else if ((master_clear) || (clear_mask_register))
                request_register[req_reg_bit_i] <= 1'b0;
            else if ((write_request_register) && (internal_data_bus[1:0] == bit_select[req_reg_bit_i]))
                request_register[req_reg_bit_i] <= internal_data_bus[2];
            else if ((end_of_process_internal) && (dma_acknowledge_internal[req_reg_bit_i]))
                request_register[req_reg_bit_i] <= 1'b0;
            else
                request_register[req_reg_bit_i] <= request_register[req_reg_bit_i];
        end
    end
    endgenerate

    //
    // Latch DMA Request
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_request_ff <= 0;
        else if (master_clear)
            dma_request_ff <= 0;
        else
            dma_request_ff <= dreq_sense_active_low ? ~dma_request : dma_request;
    end

    //
    // Edge sense
    //
    genvar req_lock_bit_i;
    generate
    for (req_lock_bit_i = 0; req_lock_bit_i < 4; req_lock_bit_i = req_lock_bit_i + 1) begin : REQUEST_LCOK
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                dma_request_lock[req_lock_bit_i] <= 1'b0;
            else if ((master_clear) || (clear_mask_register))
                dma_request_lock[req_lock_bit_i] <= 1'b0;
            else if (~edge_request[req_lock_bit_i])
                dma_request_lock[req_lock_bit_i] <= 1'b0;
            else if (cpu_clock_negedge & encoded_dma[req_lock_bit_i]  &  dma_acknowledge_internal[req_lock_bit_i])
                dma_request_lock[req_lock_bit_i] <= 1'b1;
            else if (~dma_request_ff[req_lock_bit_i] & ~dma_acknowledge_internal[req_lock_bit_i])
                dma_request_lock[req_lock_bit_i] <= 1'b0;
            else
                dma_request_lock[req_lock_bit_i] <= dma_request_lock[req_lock_bit_i];
        end
    end
    endgenerate

    //
    // DMA Request
    //
    always_comb begin
        dma_request_state   = dma_request_ff;
        dma_request_state   = dma_request_state & ~dma_request_lock;
        dma_request_state   = dma_request_state & ~mask_register;
        dma_request_state   = dma_request_state | request_register;
        encoded_dma         = dma_request_state;
        encoded_dma         = rotating_priority ? rotate_right(encoded_dma, dma_rotate) : encoded_dma;
        encoded_dma         = resolv_priority(encoded_dma);
        encoded_dma         = rotating_priority ? rotate_left(encoded_dma, dma_rotate) : encoded_dma;
        encoded_dma         = controller_disable ? 4'b000 : encoded_dma;
    end

endmodule

