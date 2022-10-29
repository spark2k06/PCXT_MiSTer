//
// KF8237_Timing_And_Control
// Timing And Control Logic
//
// Written by Kitune-san
//
`include "KF8237_Common_Package.svh"

`define TRANSFER_TYPE_VERIFY    (2'b00)
`define TRANSFER_TYPE_WRITE     (2'b01)
`define TRANSFER_TYPE_READ      (2'b10)
`define TRANSFER_TYPE_NONE      (2'b11)

`define TRANSFER_MODE_DEMAND    (2'b00)
`define TRANSFER_MODE_SINGLE    (2'b01)
`define TRANSFER_MODE_BLOCK     (2'b10)
`define TRANSFER_MODE_CASCADE   (2'b11)

module KF8237_Timing_And_Control (
    input   logic           clock,
    input   logic           cpu_clock_posedge,
    input   logic           cpu_clock_negedge,
    input   logic           reset,

    // Internal Bus
    input   logic   [7:0]   internal_data_bus,
    // -- write
    input   logic           write_command_register,
    input   logic           write_mode_register,
    // -- read
    input   logic           read_status_register,
    // -- software command
    input   logic           master_clear,

    // Internal signals
    output  logic   [1:0]   dma_rotate,
    output  logic   [3:0]   edge_request,
    input   logic   [3:0]   dma_request_state,
    input   logic   [3:0]   encoded_dma,
    output  logic   [3:0]   dma_acknowledge_internal,
    output  logic   [3:0]   transfer_register_select,
    output  logic           initialize_current_register,
    output  logic           address_hold_config,
    output  logic           decrement_address_config,
    output  logic           next_word,
    input   logic           update_high_address,
    input   logic           underflow,
    output  logic           end_of_process_internal,
    output  logic           lock_bus_control,
    output  logic           output_temporary_data,
    output  logic   [7:0]   temporary_register,
    output  logic   [3:0]   terminal_count_state,

    // External signals
    output  logic           hold_request,
    input   logic           hold_acknowledge,
    output  logic   [3:0]   dma_acknowledge,
    output  logic           address_enable,
    output  logic           address_strobe,
    output  logic           output_highst_address,
    output  logic           memory_read_n,
    output  logic           memory_write_n,
    output  logic           io_read_n_out,
    output  logic           io_read_n_io,
    output  logic           io_write_n_out,
    output  logic           io_write_n_io,
    input   logic           ready,
    input   logic           end_of_process_n_in,
    output  logic           end_of_process_n_out
);
    import KF8237_Common_Package::bit2num;

    // State
    typedef enum { SI, S0, S1, S2, S3, SW, S4 } state_t;

    state_t         state;
    state_t         next_state;
    logic           next_s4;
    logic   [1:0]   bit_select[4] = '{ 2'b00, 2'b01, 2'b10, 2'b11 };
    logic           memory_to_memory_enable;
    logic           chanel_0_address_hold_enable;
    logic           compressed_timing;
    logic           extended_write_selection;
    logic           dack_sense_active_high;
    logic   [1:0]   transfer_type[4];
    logic           autoinitialization_enable[4];
    logic           address_decrement_select[4];
    logic   [1:0]   transfer_mode[4];
    logic   [1:0]   dma_select;
    logic   [3:0]   dma_acknowledge_ff;
    logic           terminal_count;
    logic           reoutput_high_address;
    logic           external_end_of_process;
    logic           prev_read_status_register;


    //
    // Command Register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            memory_to_memory_enable         <= 1'b0;
            chanel_0_address_hold_enable    <= 1'b0;
            compressed_timing               <= 1'b0;
            extended_write_selection        <= 1'b0;
            dack_sense_active_high          <= 1'b0;
        end
        else if (master_clear) begin
            memory_to_memory_enable         <= 1'b0;
            chanel_0_address_hold_enable    <= 1'b0;
            compressed_timing               <= 1'b0;
            extended_write_selection        <= 1'b0;
            dack_sense_active_high          <= 1'b0;
        end
        else if (write_command_register) begin
            memory_to_memory_enable         <= internal_data_bus[0];
            chanel_0_address_hold_enable    <= internal_data_bus[1];
            compressed_timing               <= internal_data_bus[3];
            extended_write_selection        <= internal_data_bus[5];
            dack_sense_active_high          <= internal_data_bus[7];
        end
        else begin
            memory_to_memory_enable         <= memory_to_memory_enable;
            chanel_0_address_hold_enable    <= chanel_0_address_hold_enable;
            compressed_timing               <= compressed_timing;
            extended_write_selection        <= extended_write_selection;
            dack_sense_active_high          <= dack_sense_active_high;
        end
    end

    //
    // Mode Registers
    //
    genvar mode_reg_bit_i;
    generate
    for (mode_reg_bit_i = 0; mode_reg_bit_i < 4; mode_reg_bit_i = mode_reg_bit_i + 1) begin : MODE_REGISTERS
        always_ff @(posedge clock, posedge reset) begin
            if (reset) begin
                transfer_type[mode_reg_bit_i]               <= 2'b00;
                autoinitialization_enable[mode_reg_bit_i]   <= 1'b0;
                address_decrement_select[mode_reg_bit_i]    <= 1'b0;
                transfer_mode[mode_reg_bit_i]               <= 2'b00;
            end
            else if (master_clear) begin
                transfer_type[mode_reg_bit_i]               <= 2'b00;
                autoinitialization_enable[mode_reg_bit_i]   <= 1'b0;
                address_decrement_select[mode_reg_bit_i]    <= 1'b0;
                transfer_mode[mode_reg_bit_i]               <= 2'b00;
            end
            else if ((write_mode_register) && (internal_data_bus[1:0] == bit_select[mode_reg_bit_i])) begin
                transfer_type[mode_reg_bit_i]               <= (internal_data_bus[7:6] != `TRANSFER_MODE_CASCADE) ? internal_data_bus[3:2] : `TRANSFER_TYPE_NONE;
                autoinitialization_enable[mode_reg_bit_i]   <= internal_data_bus[4];
                address_decrement_select[mode_reg_bit_i]    <= internal_data_bus[5];
                transfer_mode[mode_reg_bit_i]               <= internal_data_bus[7:6];
            end
            else begin
                transfer_type[mode_reg_bit_i]               <= transfer_type[mode_reg_bit_i];
                autoinitialization_enable[mode_reg_bit_i]   <= autoinitialization_enable[mode_reg_bit_i];
                address_decrement_select[mode_reg_bit_i]    <= address_decrement_select[mode_reg_bit_i];
                transfer_mode[mode_reg_bit_i]               <= transfer_mode[mode_reg_bit_i];
            end
        end

        assign  edge_request[mode_reg_bit_i] = ((transfer_mode[mode_reg_bit_i] == `TRANSFER_MODE_SINGLE)
                                             || (transfer_mode[mode_reg_bit_i] == `TRANSFER_MODE_BLOCK));
    end
    endgenerate

    //
    // State Machine
    //
    always_comb begin
        next_state = state;
        next_s4    = 1'b0;

        casez (state)
            SI: begin
                if (0 != encoded_dma)
                    next_state = S0;
            end
            S0: begin
                if (hold_acknowledge)
                    next_state = S1;
            end
            S1: begin
                if (transfer_mode[dma_select] == `TRANSFER_MODE_CASCADE) begin
                    next_state = S4;
                    next_s4    = 1'b1;
                end
                else
                    next_state = S2;
            end
            S2: begin
                if (~compressed_timing)
                    next_state = S3;
                else if (transfer_type[dma_select] == `TRANSFER_TYPE_VERIFY) begin
                    if (ready)
                        next_state = S4;
                    next_s4    = 1'b1;
                end
                else
                    next_state = SW;
            end
            S3: begin
                if (transfer_type[dma_select] == `TRANSFER_TYPE_VERIFY) begin
                    if (ready)
                        next_state = S4;
                    next_s4    = 1'b1;
                end
                else
                    next_state = SW;
            end
            SW: begin
                if (ready)
                    next_state = S4;
                next_s4    = 1'b1;
            end
            S4: begin
                if (transfer_mode[dma_select] == `TRANSFER_MODE_CASCADE)
                    if (0 == (dma_acknowledge_internal & dma_request_state))
                        next_state = SI;
                    else
                        next_state = S4;
                else if (transfer_mode[dma_select] == `TRANSFER_MODE_SINGLE)
                    next_state = SI;
                else if ((transfer_mode[dma_select] == `TRANSFER_MODE_DEMAND) && (0 == (dma_acknowledge_internal & dma_request_state)))
                    next_state = SI;
                else if (end_of_process_internal)
                    next_state = SI;
                else
                    next_state = (reoutput_high_address) ? S1 : S2;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state <= SI;
        else if (master_clear)
            state <= SI;
        else if (cpu_clock_negedge)
            state <= next_state;
        else
            state <= state;
    end

    //
    // Sample DREQn Line
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_acknowledge_internal <= 0;
        else if (master_clear)
            dma_acknowledge_internal <= 0;
        else if (state == SI)
            dma_acknowledge_internal <= encoded_dma;
        else
            dma_acknowledge_internal <= dma_acknowledge_internal;
    end

    assign  dma_select = bit2num(dma_acknowledge_internal);

    //
    // DMA Rotate
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_rotate <= 2'd3;
        else if (master_clear)
            dma_rotate <= 2'd3;
        else if (state == S0)
            dma_rotate <= dma_select;
        else
            dma_rotate <= dma_rotate;
    end

    //
    // Internal signals
    //
    always_comb begin
        address_hold_config         = ((4'b0001 == dma_acknowledge_internal) & (chanel_0_address_hold_enable));
        decrement_address_config    = address_decrement_select[dma_select];
        next_word                   = ((next_state == S4) && (transfer_mode[dma_select] != `TRANSFER_MODE_CASCADE)) ? 1'b1 : 1'b0;
        // TODO: output_temporary_data  (Memory-to-Memory)

        casez (state)
            SI: begin
                transfer_register_select    = 0;
                initialize_current_register = 0;
                lock_bus_control            = 0;
            end
            S0: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = 0;
                lock_bus_control            = 1'b0;
            end
            S1: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = 0;
                lock_bus_control            = 1'b1;
            end
            S2: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = 0;
                lock_bus_control            = 1'b1;
            end
            S3: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = 0;
                lock_bus_control            = 1'b1;
            end
            SW: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = 0;
                lock_bus_control            = 1'b1;
            end
            S4: begin
                transfer_register_select    = dma_acknowledge_internal;
                initialize_current_register = autoinitialization_enable[dma_select] & end_of_process_internal;
                lock_bus_control            = 1'b1;
            end
            default: begin
                transfer_register_select    = 0;
                initialize_current_register = 0;
                lock_bus_control            = 0;
            end
        endcase
    end

    //
    // Hold Request Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            hold_request <= 1'b0;
        else if (master_clear)
            hold_request <= 1'b0;
        else if (cpu_clock_posedge)
            if (next_state == S0)
                hold_request <= 1'b1;
            else if (next_state == SI)
                hold_request <= 1'b0;
            else
                hold_request <= hold_request;
        else
            hold_request <= hold_request;
    end

    //
    // Address Enable Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            address_enable <= 1'b0;
        else if (master_clear)
            address_enable <= 1'b0;
        else if (cpu_clock_posedge)
            if (transfer_mode[dma_select] == `TRANSFER_MODE_CASCADE)
                address_enable <= 1'b0;
            else if (state == S1)
                address_enable <= 1'b1;
            else if (state == SI)
                address_enable <= 1'b0;
            else
                address_enable <= address_enable;
        else
            address_enable <= address_enable;
    end

    //
    // Address Strobe Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            address_strobe <= 1'b0;
        else if (master_clear)
            address_strobe <= 1'b0;
        else if (cpu_clock_posedge)
            if (transfer_mode[dma_select] == `TRANSFER_MODE_CASCADE)
                address_strobe <= 1'b0;
            else if (state == S1)
                address_strobe <= 1'b1;
            else
                address_strobe <= 1'b0;
        else
            address_strobe <= address_strobe;
    end

    //
    // Output Highst Address On Data Bus Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            output_highst_address <= 1'b0;
        else if (master_clear)
            output_highst_address <= 1'b0;
        else if (cpu_clock_negedge)
            if (transfer_mode[dma_select] == `TRANSFER_MODE_CASCADE)
                output_highst_address <= 1'b0;
            else if ((state == S1) && (next_state == S2))
                output_highst_address <= 1'b1;
            else
                output_highst_address <= 1'b0;
        else
            output_highst_address <= output_highst_address;
    end

    //
    // DMA Acknowledge Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_acknowledge_ff <= 0;
        else if (master_clear)
            dma_acknowledge_ff <= 0;
        else if (cpu_clock_negedge)
            if (next_state == S2)
                dma_acknowledge_ff <= dma_acknowledge_internal;
            else if (next_state == SI)
                dma_acknowledge_ff <= 0;
            else
                dma_acknowledge_ff <= dma_acknowledge_ff;
        else
            dma_acknowledge_ff <= dma_acknowledge_ff;
    end

    assign  dma_acknowledge = (dack_sense_active_high) ? dma_acknowledge_ff : ~dma_acknowledge_ff;

    //
    // IO Read Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            io_read_n_io <= 1'b1;
        else if (master_clear)
            io_read_n_io <= 1'b1;
        else if (cpu_clock_posedge)
            if ((state == S1) && (transfer_type[dma_select] == `TRANSFER_TYPE_WRITE))
                io_read_n_io <= 1'b0;
            else if (state == SI)
                io_read_n_io <= 1'b1;
            else
                io_read_n_io <= io_read_n_io;
        else
            io_read_n_io <= io_read_n_io;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            io_read_n_out <= 1'b1;
        else if (master_clear)
            io_read_n_out <= 1'b1;
        else if (cpu_clock_posedge)
            if ((state == S2) && (transfer_type[dma_select] == `TRANSFER_TYPE_WRITE))
                io_read_n_out <= 1'b0;
            else if (state == S4)
                io_read_n_out <= 1'b1;
            else
                io_read_n_out <= io_read_n_out;
        else
            io_read_n_out <= io_read_n_out;
    end

    //
    // Memory Read Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            memory_read_n <= 1'b1;
        else if (master_clear)
            memory_read_n <= 1'b1;
        else if (cpu_clock_posedge)
            if ((state == S2) && (transfer_type[dma_select] == `TRANSFER_TYPE_READ))
                memory_read_n <= 1'b0;
            else if (state == S4)
                memory_read_n <= 1'b1;
            else
                memory_read_n <= memory_read_n;
        else
            memory_read_n <= memory_read_n;
    end

    //
    // IO Write Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            io_write_n_io <= 1'b1;
        else if (master_clear)
            io_write_n_io <= 1'b1;
        else if (cpu_clock_posedge)
            if ((state == S1) && (transfer_type[dma_select] == `TRANSFER_TYPE_READ))
                io_write_n_io <= 1'b0;
            else if (state == SI)
                io_write_n_io <= 1'b1;
            else
                io_write_n_io <= io_write_n_io;
        else
            io_write_n_io <= io_write_n_io;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            io_write_n_out <= 1'b1;
        else if (master_clear)
            io_write_n_out <= 1'b1;
        else if (cpu_clock_posedge)
            if (state == S4)
                io_write_n_out <= 1'b1;
            else if (transfer_type[dma_select] == `TRANSFER_TYPE_READ)
                if ((state == S2) && ((extended_write_selection) || (compressed_timing)))
                    io_write_n_out <= 1'b0;
                else if (state == S3)
                    io_write_n_out <= 1'b0;
                else
                    io_write_n_out <= io_write_n_out;
            else
                io_write_n_out <= io_write_n_out;
        else
            io_write_n_out <= io_write_n_out;
    end

    //
    // Memory Write Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            memory_write_n <= 1'b1;
        else if (master_clear)
            memory_write_n <= 1'b1;
        else if (cpu_clock_posedge)
            if (state == S4)
                memory_write_n <= 1'b1;
            else if (transfer_type[dma_select] == `TRANSFER_TYPE_WRITE)
                if ((state == S2) && ((extended_write_selection) || (compressed_timing)))
                    memory_write_n <= 1'b0;
                else if (state == S3)
                    memory_write_n <= 1'b0;
                else
                    memory_write_n <= memory_write_n;
            else
                memory_write_n <= memory_write_n;
        else
            memory_write_n <= memory_write_n;
    end

    //
    // Update High Address Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            reoutput_high_address <= 1'b0;
        else if (master_clear)
            reoutput_high_address <= 1'b0;
        else if (state == S2)
            reoutput_high_address <= 1'b0;
        else if ((cpu_clock_negedge) && (next_word))
            reoutput_high_address <= update_high_address;
        else
            reoutput_high_address <= reoutput_high_address;
    end

    //
    // Terminal Count Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            terminal_count <= 1'b0;
        else if (master_clear)
            terminal_count <= 1'b0;
        else if (cpu_clock_posedge)
            if (state == S4)
                terminal_count <= 1'b0;
            else if (next_s4)
                terminal_count <= underflow;
            else
                terminal_count <= terminal_count;
        else
            terminal_count <= terminal_count;
    end

    assign  end_of_process_n_out = ~terminal_count;

    //
    // End Of Process Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            external_end_of_process <= 1'b0;
        else if (master_clear)
            external_end_of_process <= 1'b0;
        else if (cpu_clock_negedge)
            if (state == SI)
                external_end_of_process <= 1'b0;
            else if ((next_state == S2) && (~end_of_process_n_in))
                external_end_of_process <= 1'b1;
            else
                external_end_of_process <= external_end_of_process;
        else
            external_end_of_process <= external_end_of_process;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            end_of_process_internal <= 1'b0;
        else if (master_clear)
            end_of_process_internal <= 1'b0;
        else if (cpu_clock_negedge)
            if (next_state == S4)
                end_of_process_internal <= terminal_count | external_end_of_process;
            else
                end_of_process_internal <= 1'b0;
        else
            end_of_process_internal <= end_of_process_internal;
    end

    //
    // Status Register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_read_status_register <= 1'b0;
        else if (cpu_clock_negedge)
            prev_read_status_register <= read_status_register;
        else
            prev_read_status_register <= prev_read_status_register;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            terminal_count_state <= 0;
        else if (master_clear)
            terminal_count_state <= 0;
        else if (cpu_clock_negedge)
            if (prev_read_status_register & ~read_status_register)
                terminal_count_state <= 0;
            else if (end_of_process_internal)
                terminal_count_state <= terminal_count_state | dma_acknowledge_internal;
            else
                terminal_count_state <= terminal_count_state;
        else
            terminal_count_state <= terminal_count_state;
    end

    // TODO: temporary_register (Memory-to-Memory)

endmodule

