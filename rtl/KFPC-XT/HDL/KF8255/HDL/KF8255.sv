//
// KF8255
// 8255A-LIKE PROGRAMMABLE PERIPHERAL INTERFACE
//
// Written by Kitune-san
//

module KF8255 (
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
    input   logic   [7:0]   port_a_in,
    output  logic   [7:0]   port_a_out,
    output  logic           port_a_io,

    input   logic   [7:0]   port_b_in,
    output  logic   [7:0]   port_b_out,
    output  logic           port_b_io,

    input   logic   [7:0]   port_c_in,
    output  logic   [7:0]   port_c_out,
    output  logic   [7:0]   port_c_io
);

    //
    // Data Bus Buffer & Read/Write Control Logic (1)
    //
    logic   [7:0]   internal_data_bus;
    logic           write_port_a;
    logic           write_port_b;
    logic           write_port_c;
    logic           write_control;
    logic           read_port_a;
    logic           read_port_b;
    logic           read_port_c;

    KF8255_Control_Logic u_Control_Logic (
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
        .write_port_a           (write_port_a),
        .write_port_b           (write_port_b),
        .write_port_c           (write_port_c),
        .write_control          (write_control),
        .read_port_a            (read_port_a),
        .read_port_b            (read_port_b),
        .read_port_c            (read_port_c)
    );


    //
    // Group A Control
    //
    logic   [3:0]   group_a_bus;
    logic           write_group_a;
    logic           update_group_a_mode;

    assign group_a_bus   = internal_data_bus[6:3];
    assign write_group_a = write_control & internal_data_bus[7];

    logic   [1:0]   group_a_mode_reg;
    logic           group_a_port_a_io_reg;
    logic           group_a_port_c_io_reg;

    KF8255_Group u_Group_A (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (group_a_bus),
        .write_register         (write_group_a),

        // Control Data Registers
        .update_group_mode      (update_group_a_mode),
        .mode_select_reg        (group_a_mode_reg),
        .port_1_io_reg          (group_a_port_a_io_reg),
        .port_2_io_reg          (group_a_port_c_io_reg)
    );


    //
    // Group B Control
    //
    logic   [3:0]   group_b_bus;
    logic           write_group_b;
    logic           update_group_b_mode;

    assign group_b_bus   = {1'b0, internal_data_bus[2:0]};
    assign write_group_b = write_control & internal_data_bus[7];

    logic   [1:0]   group_b_mode_reg;
    logic           group_b_port_b_io_reg;
    logic           group_b_port_c_io_reg;

    KF8255_Group u_Group_B (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (group_b_bus),
        .write_register         (write_group_b),

        // Control Data Registers
        .update_group_mode      (update_group_b_mode),
        .mode_select_reg        (group_b_mode_reg),
        .port_1_io_reg          (group_b_port_b_io_reg),
        .port_2_io_reg          (group_b_port_c_io_reg)
    );


    //
    // Group A Port A
    //
    logic           port_a_strobe;
    logic           port_a_hiz;
    logic   [7:0]   port_a_read_data;

    KF8255_Port u_Port_A (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_port             (write_port_a),
        .update_mode            (update_group_a_mode),

        // Control Data Registers
        .mode_select_reg        (group_a_mode_reg),
        .port_io_reg            (group_a_port_a_io_reg),

        // Signals
        .strobe                 (port_a_strobe),
        .hiz                    (port_a_hiz),

        // Ports
        .port_io                (port_a_io),
        .port_out               (port_a_out),
        .port_in                (port_a_in),
        .read                   (port_a_read_data)
    );


    //
    // Group B Port B
    //
    logic           port_b_strobe;
    logic   [7:0]   port_b_read_data;

    KF8255_Port u_Port_B (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_port             (write_port_b),
        .update_mode            (update_group_b_mode),

        // Control Data Registers
        .mode_select_reg        (group_b_mode_reg),
        .port_io_reg            (group_b_port_b_io_reg),

        // Signals
        .strobe                 (port_b_strobe),
        .hiz                    (1'b0),

        // Ports
        .port_io                (port_b_io),
        .port_out               (port_b_out),
        .port_in                (port_b_in),
        .read                   (port_b_read_data)
    );


    //
    // Port C
    //
    logic           write_port_c_bit_set;
    logic   [7:0]   port_c_read_data;

    assign write_port_c_bit_set = write_control & (~internal_data_bus[7]);

    KF8255_Port_C u_Port_C (
        // Bus
        .clock                  (clock),
        .reset                  (reset),
        .chip_select_n          (chip_select_n),
        .read_enable_n          (read_enable_n),

        .internal_data_bus      (internal_data_bus),
        .write_port_a           (write_port_a),
        .write_port_b           (write_port_b),
        .write_port_c_bit_set   (write_port_c_bit_set),
        .write_port_c           (write_port_c),
        .read_port_a            (read_port_a),
        .read_port_b            (read_port_b),
        .read_port_c            (read_port_c),
        .update_group_a_mode    (update_group_a_mode),
        .update_group_b_mode    (update_group_b_mode),

        // Control Data Registers
        .group_a_mode_reg       (group_a_mode_reg),
        .group_b_mode_reg       (group_b_mode_reg),
        .group_a_port_a_io_reg  (group_a_port_a_io_reg),
        .group_b_port_b_io_reg  (group_b_port_b_io_reg),
        .group_a_port_c_io_reg  (group_a_port_c_io_reg),
        .group_b_port_c_io_reg  (group_b_port_c_io_reg),

        // Signals
        .port_a_strobe          (port_a_strobe),
        .port_b_strobe          (port_b_strobe),
        .port_a_hiz             (port_a_hiz),

        // Ports
        .port_c_io              (port_c_io),
        .port_c_out             (port_c_out),
        .port_c_in              (port_c_in),
        .port_c_read            (port_c_read_data)
    );


    //
    // Data Bus Buffer & Read/Write Control Logic (2)
    //
    always_comb begin
        data_bus_out = 8'b00000000;
        if (read_port_a)
            data_bus_out = port_a_read_data;
        else if (read_port_b)
            data_bus_out = port_b_read_data;
        else if (read_port_c)
            data_bus_out = port_c_read_data;
    end

endmodule
