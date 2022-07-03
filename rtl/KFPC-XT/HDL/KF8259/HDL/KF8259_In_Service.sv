//
// KF8259_In_Service
//
// Written by Kitune-san
//
`include "KF8259_Common_Package.svh"

module KF8259_In_Service (
    input   logic           clock,
    input   logic           reset,

    // Inputs
    input   logic   [2:0]   priority_rotate,
    input   logic   [7:0]   interrupt_special_mask,
    input   logic   [7:0]   interrupt,
    input   logic           latch_in_service,
    input   logic   [7:0]   end_of_interrupt,

    // Outputs
    output  logic   [7:0]   in_service_register,
    output  logic   [7:0]   highest_level_in_service
);
    import KF8259_Common_Package::rotate_right;
    import KF8259_Common_Package::rotate_left;
    import KF8259_Common_Package::resolv_priority;

    //
    // In service register
    //
    logic   [7:0]   next_in_service_register;

    assign next_in_service_register = (in_service_register & ~end_of_interrupt)
                                     | (latch_in_service == 1'b1 ? interrupt : 8'b00000000);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            in_service_register <= 8'b00000000;
        else
            in_service_register <= next_in_service_register;
    end

    //
    // Get Highst level in service
    //
    logic   [7:0]   next_highest_level_in_service;

    always_comb begin
        next_highest_level_in_service = next_in_service_register & ~interrupt_special_mask;
        next_highest_level_in_service = rotate_right(next_highest_level_in_service, priority_rotate);
        next_highest_level_in_service = resolv_priority(next_highest_level_in_service);
        next_highest_level_in_service = rotate_left(next_highest_level_in_service, priority_rotate);
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            highest_level_in_service <= 8'b00000000;
        else
            highest_level_in_service <= next_highest_level_in_service;
    end

endmodule
