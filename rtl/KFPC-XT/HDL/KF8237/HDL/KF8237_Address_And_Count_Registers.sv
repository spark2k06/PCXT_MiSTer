//
// KF8237_Address_And_Count_Registers
// Address And Count Registers
//
// Written by Kitune-san
//
`include "KF8237_Common_Package.svh"

module KF8237_Address_And_Count_Registers (
    // Bus
    input   logic           clock,
    input   logic           cpu_clock_posedge,
    input   logic           cpu_clock_negedge,
    input   logic           reset,

    // Internal Bus
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   read_address_or_count,
    // -- write
    input   logic   [3:0]   write_base_and_current_address,
    input   logic   [3:0]   write_base_and_current_word_count,
    // -- software command
    input   logic           clear_byte_pointer,
    input   logic           set_byte_pointer,
    input   logic           master_clear,
    // -- read
    input   logic   [3:0]   read_current_address,
    input   logic   [3:0]   read_current_word_count,

    // Internal signals
    input   logic   [3:0]   transfer_register_select,
    input   logic           initialize_current_register,
    input   logic           address_hold_config,
    input   logic           decrement_address_config,
    input   logic           next_word,
    output  logic           underflow,
    output  logic           update_high_address,
    output  logic   [15:0]  transfer_address
);
    import KF8237_Common_Package::bit2num;

    logic   [3:0]   prev_read_current_address;
    logic   [3:0]   prev_read_current_word_count;
    logic           byte_pointer;
    logic   [15:0]  base_address[4];
    logic   [15:0]  current_address[4];
    logic   [15:0]  base_word_count[4];
    logic   [15:0]  current_word_count[4];
    logic   [15:0]  temporary_address;
    logic   [16:0]  temporary_word_count;


    //
    // Byte Pointer
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_read_current_address <= 0;
        else
            prev_read_current_address <= read_current_address;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_read_current_word_count <= 0;
        else
            prev_read_current_word_count <= read_current_word_count;
    end

    wire    update_byte_pointer =  (0 != write_base_and_current_address)
                                || (0 != write_base_and_current_word_count)
                                || ((0 != prev_read_current_address) && (0 == read_current_address))
                                || ((0 != prev_read_current_word_count) && (0 == read_current_word_count));

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            byte_pointer <= 1'b0;
        else if ((master_clear) || (clear_byte_pointer))
            byte_pointer <= 1'b0;
        else if (set_byte_pointer)
            byte_pointer <= 1'b1;
        else if (update_byte_pointer)
             if (byte_pointer)
                 byte_pointer <= 1'b0;
             else
                 byte_pointer <= 1'b1;
        else
            byte_pointer <= byte_pointer;
    end

    //
    // Address & Current Word Registers
    //
    genvar dma_ch_i;
    generate
    for (dma_ch_i = 0; dma_ch_i < 4; dma_ch_i = dma_ch_i + 1) begin : ADDRESS_AND_COUNT_REGISTERS
        //
        // Base Address Register
        //
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                base_address[dma_ch_i] <= 16'h00;
            else if (master_clear)
                base_address[dma_ch_i] <= 16'h00;
            else if (write_base_and_current_address[dma_ch_i])
                if (~byte_pointer)
                    base_address[dma_ch_i][7:0]  <= internal_data_bus;
                else
                    base_address[dma_ch_i][15:8] <= internal_data_bus;
            else
                base_address[dma_ch_i] <= base_address[dma_ch_i];
        end

        //
        // Base Word Count Register
        //
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                base_word_count[dma_ch_i] <= 16'h00;
            else if (master_clear)
                base_word_count[dma_ch_i] <= 16'h00;
            else if (write_base_and_current_word_count[dma_ch_i])
                if (~byte_pointer)
                    base_word_count[dma_ch_i][7:0]  <= internal_data_bus;
                else
                    base_word_count[dma_ch_i][15:8] <= internal_data_bus;
            else
                base_word_count[dma_ch_i] <= base_word_count[dma_ch_i];
        end

        //
        // Current Address Register
        //
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                current_address[dma_ch_i] <= 16'h00;
            else if (master_clear)
                current_address[dma_ch_i] <= 16'h00;
            else if (write_base_and_current_address[dma_ch_i])
                if (~byte_pointer)
                    current_address[dma_ch_i][7:0]  <= internal_data_bus;
                else
                    current_address[dma_ch_i][15:8] <= internal_data_bus;
            else if ((transfer_register_select[dma_ch_i]) && (initialize_current_register))
                current_address[dma_ch_i] <= base_address[dma_ch_i];
            else if ((transfer_register_select[dma_ch_i]) && (next_word) && (cpu_clock_negedge))
                current_address[dma_ch_i] <= temporary_address;
            else
                current_address[dma_ch_i] <= current_address[dma_ch_i];
        end

        //
        // Current Word Register
        //
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                current_word_count[dma_ch_i] <= 16'h00;
            else if (master_clear)
                current_word_count[dma_ch_i] <= 16'h00;
            else if (write_base_and_current_word_count[dma_ch_i])
                if (~byte_pointer)
                    current_word_count[dma_ch_i][7:0]  <= internal_data_bus;
                else
                    current_word_count[dma_ch_i][15:8] <= internal_data_bus;
            else if ((transfer_register_select[dma_ch_i]) && (initialize_current_register))
                current_word_count[dma_ch_i] <= base_word_count[dma_ch_i];
            else if ((transfer_register_select[dma_ch_i]) && (next_word) && (cpu_clock_negedge))
                current_word_count[dma_ch_i] <= temporary_word_count[15:0];
            else
                current_word_count[dma_ch_i] <= current_word_count[dma_ch_i];
        end
    end
    endgenerate


    //
    // Selects DMA CH
    //
    wire    [1:0]   dma_select = bit2num(transfer_register_select);

    //
    // Temp Address Register
    //
    always_comb begin
        temporary_address = current_address[dma_select];
        if (address_hold_config)
            temporary_address = temporary_address;
        else if (decrement_address_config)
            temporary_address = temporary_address - 16'h01;
        else
            temporary_address = temporary_address + 16'h01;
    end

    //
    // Temp Word Count Register
    //
    always_comb begin
        temporary_word_count = {1'b1, current_word_count[dma_select]};
        temporary_word_count = temporary_word_count - 17'h01;
    end

    //
    // Detects Underflow of Word Count
    //
    assign  underflow = ~temporary_word_count[16];

    //
    // Detects To Update Address[15-8]
    //
    assign  update_high_address = (transfer_address[8] != temporary_address[8]);

    //
    // Transfer Addres
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            transfer_address <= 0;
        else if (master_clear)
            transfer_address <= 0;
        else if (cpu_clock_negedge)
            transfer_address <= current_address[dma_select];
        else
            transfer_address <= transfer_address;
    end

    //
    // Reads Registers
    //
    logic   [15:0]  read_register;

    always_comb begin
        if (read_current_address[0])            read_register = current_address[0];
        else if (read_current_address[1])       read_register = current_address[1];
        else if (read_current_address[2])       read_register = current_address[2];
        else if (read_current_address[3])       read_register = current_address[3];
        else if (read_current_word_count[0])    read_register = current_word_count[0];
        else if (read_current_word_count[1])    read_register = current_word_count[1];
        else if (read_current_word_count[2])    read_register = current_word_count[2];
        else if (read_current_word_count[3])    read_register = current_word_count[3];
        else                                    read_register = 16'h00;;

        if (~byte_pointer)
            read_address_or_count = read_register[7:0];
        else
            read_address_or_count = read_register[15:8];
    end

endmodule

