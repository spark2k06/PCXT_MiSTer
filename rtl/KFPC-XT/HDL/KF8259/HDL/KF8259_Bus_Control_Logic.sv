//
// KF8259_Bus_Control_Logic
// Data Bus Buffer & Read/Write Control Logic
//
// Written by Kitune-san
//
module KF8259_Bus_Control_Logic (
    input   logic           clock,
    input   logic           reset,

    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,
    input   logic           address,
    input   logic   [7:0]   data_bus_in,

    // Internal Bus
    output  logic   [7:0]   internal_data_bus,
    output  logic           write_initial_command_word_1,
    output  logic           write_initial_command_word_2_4,
    output  logic           write_operation_control_word_1,
    output  logic           write_operation_control_word_2,
    output  logic           write_operation_control_word_3,
    output  logic           read
);

    //
    // Internal Signals
    //
    logic   prev_write_enable_n;
    logic   write_flag;
    logic   stable_address;

    //
    // Write Control
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            internal_data_bus <= 8'b00000000;
        else if (~write_enable_n & ~chip_select_n)
            internal_data_bus <= data_bus_in;
        else
            internal_data_bus <= internal_data_bus;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_write_enable_n <= 1'b1;
        else if (chip_select_n)
            prev_write_enable_n <= 1'b1;
        else
            prev_write_enable_n <= write_enable_n;
    end
    assign write_flag = ~prev_write_enable_n & write_enable_n;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            stable_address <= 1'b0;
        else
            stable_address <= address;
    end

    // Generate write request flags
    assign write_initial_command_word_1   = write_flag & ~stable_address & internal_data_bus[4];
    assign write_initial_command_word_2_4 = write_flag & stable_address;
    assign write_operation_control_word_1 = write_flag & stable_address;
    assign write_operation_control_word_2 = write_flag & ~stable_address & ~internal_data_bus[4] & ~internal_data_bus[3];
    assign write_operation_control_word_3 = write_flag & ~stable_address & ~internal_data_bus[4] & internal_data_bus[3];

    //
    // Read Control
    //
    assign read = ~read_enable_n  & ~chip_select_n;

endmodule

