//
// KF8253
// PROGRAMMABLE INTERVAL TIMER
//
// Written by Kitune-san
//

module KF8253 (
    // Bus
    input   logic           clock,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,
    input   logic   [1:0]   address,
    input   logic   [7:0]   data_bus_in,

    output  logic   [7:0]   data_bus_out,

    // I/O
    input   logic           counter_0_clock,
    input   logic           counter_0_gate,
    output  logic           counter_0_out,

    input   logic           counter_1_clock,
    input   logic           counter_1_gate,
    output  logic           counter_1_out,

    input   logic           counter_2_clock,
    input   logic           counter_2_gate,
    output  logic           counter_2_out
);


    //
    // Data Bus Buffer & Read/Write Control Logic (1)
    //
    logic   [7:0]   internal_data_bus;
    logic           write_control_0;
    logic           write_control_1;
    logic           write_control_2;
    logic           write_counter_0;
    logic           write_counter_1;
    logic           write_counter_2;
    logic           read_counter_0;
    logic           read_counter_1;
    logic           read_counter_2;
    logic   [7:0]   read_counter_0_data;
    logic   [7:0]   read_counter_1_data;
    logic   [7:0]   read_counter_2_data;

    KF8253_Control_Logic u_KF8253_Control_Logic (
        // Bus
        .clock                  (clock),
        .reset                  (reset),
        .chip_select_n          (chip_select_n),
        .read_enable_n          (read_enable_n),
        .write_enable_n         (write_enable_n),
        .address                (address),
        .data_bus_in            (data_bus_in),

        // Control Signals
        .internal_data_bus      (internal_data_bus),
        .write_control_0        (write_control_0),
        .write_control_1        (write_control_1),
        .write_control_2        (write_control_2),
        .write_counter_0        (write_counter_0),
        .write_counter_1        (write_counter_1),
        .write_counter_2        (write_counter_2),
        .read_counter_0         (read_counter_0),
        .read_counter_1         (read_counter_1),
        .read_counter_2         (read_counter_2)
    );


    //
    // Counter #0
    //
    KF8253_Counter u_KF8253_Counter_0 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_0),
        .write_counter          (write_counter_0),
        .read_counter           (read_counter_0),

        .read_counter_data      (read_counter_0_data),

        // I/O
        .counter_clock          (counter_0_clock),
        .counter_gate           (counter_0_gate),
        .counter_out            (counter_0_out)
    );


    //
    // Counter #1
    //
    KF8253_Counter u_KF8253_Counter_1 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_1),
        .write_counter          (write_counter_1),
        .read_counter           (read_counter_1),

        .read_counter_data      (read_counter_1_data),

        // I/O
        .counter_clock          (counter_1_clock),
        .counter_gate           (counter_1_gate),
        .counter_out            (counter_1_out)
    );


    //
    // Counter #2
    //
    KF8253_Counter u_KF8253_Counter_2 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_2),
        .write_counter          (write_counter_2),
        .read_counter           (read_counter_2),

        .read_counter_data      (read_counter_2_data),

        // I/O
        .counter_clock          (counter_2_clock),
        .counter_gate           (counter_2_gate),
        .counter_out            (counter_2_out)
    );


    //
    // Data Bus Buffer & Read/Write Control Logic (2)
    //
    always_comb begin
        if (read_counter_0)
            data_bus_out = read_counter_0_data;
        else if (read_counter_1)
            data_bus_out = read_counter_1_data;
        else if (read_counter_2)
            data_bus_out = read_counter_2_data;
        else
            data_bus_out = 8'b00000000;
    end

endmodule

