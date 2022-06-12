//
// KF8259
// 8259A-LIKE PROGRAMMABLE INTERRUPT CONTROLLER
//
// Written by Kitune-san
//
module KF8259 (
    // Bus
    input   logic           clock,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,
    input   logic           address,
    input   logic   [7:0]   data_bus_in,
    output  logic   [7:0]   data_bus_out,
    output  logic           data_bus_io,

    // I/O
    input   logic   [2:0]   cascade_in,
    output  logic   [2:0]   cascade_out,
    output  logic           cascade_io,

    input   logic           slave_program_n,
    output  logic           buffer_enable,
    output  logic           slave_program_or_enable_buffer,

    input   logic           interrupt_acknowledge_n,
    output  logic           interrupt_to_cpu,

    input   logic   [7:0]   interrupt_request
);

    //
    // Data Bus Buffer & Read/Write Control Logic (1)
    //
    logic   [7:0]   internal_data_bus;
    logic           write_initial_command_word_1;
    logic           write_initial_command_word_2_4;
    logic           write_operation_control_word_1;
    logic           write_operation_control_word_2;
    logic           write_operation_control_word_3;
    logic           read;

    KF8259_Bus_Control_Logic u_Bus_Control_Logic (
        // Bus
        .clock                              (clock),
        .reset                              (reset),
        .chip_select_n                      (chip_select_n),
        .read_enable_n                      (read_enable_n),
        .write_enable_n                     (write_enable_n),
        .address                            (address),
        .data_bus_in                        (data_bus_in),

        // Control signals
        .internal_data_bus                  (internal_data_bus),
        .write_initial_command_word_1       (write_initial_command_word_1),
        .write_initial_command_word_2_4     (write_initial_command_word_2_4),
        .write_operation_control_word_1     (write_operation_control_word_1),
        .write_operation_control_word_2     (write_operation_control_word_2),
        .write_operation_control_word_3     (write_operation_control_word_3),
        .read                               (read)
    );

    //
    // Interrupt (Service) Control Logic
    //
    logic           out_control_logic_data;
    logic   [7:0]   control_logic_data;
    logic           level_or_edge_toriggered_config;
    logic           special_fully_nest_config;
    logic           enable_read_register;
    logic           read_register_isr_or_irr;
    logic   [7:0]   interrupt;
    logic   [7:0]   highest_level_in_service;
    logic   [7:0]   interrupt_mask;
    logic   [7:0]   interrupt_special_mask;
    logic   [7:0]   end_of_interrupt;
    logic   [2:0]   priority_rotate;
    logic           freeze;
    logic           latch_in_service;
    logic   [7:0]   clear_interrupt_request;

    KF8259_Control_Logic u_Control_Logic (
        // Bus
        .clock                              (clock),
        .reset                              (reset),

        // External input/output
        .cascade_in                         (cascade_in),
        .cascade_out                        (cascade_out),
        .cascade_io                         (cascade_io),

        .slave_program_n                    (slave_program_n),
        .slave_program_or_enable_buffer     (slave_program_or_enable_buffer),

        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .interrupt_to_cpu                   (interrupt_to_cpu),

        // Internal bus
        .internal_data_bus                  (internal_data_bus),
        .write_initial_command_word_1       (write_initial_command_word_1),
        .write_initial_command_word_2_4     (write_initial_command_word_2_4),
        .write_operation_control_word_1     (write_operation_control_word_1),
        .write_operation_control_word_2     (write_operation_control_word_2),
        .write_operation_control_word_3     (write_operation_control_word_3),

        .read                               (read),
        .out_control_logic_data             (out_control_logic_data),
        .control_logic_data                 (control_logic_data),

        // Registers to interrupt detecting logics
        .level_or_edge_toriggered_config    (level_or_edge_toriggered_config),
        .special_fully_nest_config          (special_fully_nest_config),

        // Registers to Read logics
        .enable_read_register               (enable_read_register),
        .read_register_isr_or_irr           (read_register_isr_or_irr),

        // Signals from interrupt detectiong logics
        .interrupt                          (interrupt),
        .highest_level_in_service           (highest_level_in_service),

        // Interrupt control signals
        .interrupt_mask                     (interrupt_mask),
        .interrupt_special_mask             (interrupt_special_mask),
        .end_of_interrupt                   (end_of_interrupt),
        .priority_rotate                    (priority_rotate),
        .freeze                             (freeze),
        .latch_in_service                   (latch_in_service),
        .clear_interrupt_request            (clear_interrupt_request)
    );

    //
    // Interrupt Request
    //
    logic   [7:0]   interrupt_request_register;

    KF8259_Interrupt_Request u_Interrupt_Request (
        // Bus
        .clock                              (clock),
        .reset                              (reset),

        // Inputs from control logic
        .level_or_edge_toriggered_config    (level_or_edge_toriggered_config),
        .freeze                             (freeze),
        .clear_interrupt_request            (clear_interrupt_request),
        .interrupt_mask                     (interrupt_mask),

        // External inputs
        .interrupt_request_pin              (interrupt_request),

        // Outputs
        .interrupt_request_register         (interrupt_request_register)
    );

    //
    // Priority Resolver
    //
    logic   [7:0]   in_service_register;

    KF8259_Priority_Resolver u_Priority_Resolver (
        // Inputs from control logic
        .priority_rotate                    (priority_rotate),
        .interrupt_mask                     (interrupt_mask),
        .interrupt_special_mask             (interrupt_special_mask),
        .special_fully_nest_config          (special_fully_nest_config),
        .highest_level_in_service           (highest_level_in_service),

        // Inputs
        .interrupt_request_register         (interrupt_request_register),
        .in_service_register                (in_service_register),

        // Outputs
        .interrupt                          (interrupt)
    );

    //
    // In Service
    //
    KF8259_In_Service u_In_Service (
        // Bus
        .clock                              (clock),
        .reset                              (reset),

        // Inputs
        .priority_rotate                    (priority_rotate),
        .interrupt_special_mask             (interrupt_special_mask),
        .interrupt                          (interrupt),
        .latch_in_service                   (latch_in_service),
        .end_of_interrupt                   (end_of_interrupt),

        // Outputs
        .in_service_register                (in_service_register),
        .highest_level_in_service           (highest_level_in_service)
    );

    //
    // Data Bus Buffer & Read/Write Control Logic (2)
    //
    // Data bus
    always_comb begin
        if (out_control_logic_data == 1'b1) begin
            data_bus_io  = 1'b0;
            data_bus_out = control_logic_data;
        end
        else if (read == 1'b0) begin
            data_bus_io  = 1'b1;
            data_bus_out = 8'b00000000;
        end
        else if (address == 1'b1) begin
            data_bus_io  = 1'b0;
            data_bus_out = interrupt_mask;
        end
        else if ((enable_read_register == 1'b1) && (read_register_isr_or_irr == 1'b0)) begin
            data_bus_io  = 1'b0;
            data_bus_out = interrupt_request_register;
        end
        else if ((enable_read_register == 1'b1) && (read_register_isr_or_irr == 1'b1)) begin
            data_bus_io  = 1'b0;
            data_bus_out = in_service_register;
        end
        else begin
            data_bus_io  = 1'b1;
            data_bus_out = 8'b00000000;
        end
    end

    // Read buffer enable signal
    assign  buffer_enable = (slave_program_or_enable_buffer == 1'b1) ? 1'b0 : ~data_bus_io;

endmodule

