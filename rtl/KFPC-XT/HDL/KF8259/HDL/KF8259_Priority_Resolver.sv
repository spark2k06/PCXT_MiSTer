//
// KF8255_Priority_Resolver
//
// Written by Kitune-san
//
`include "KF8259_Common_Package.svh"

module KF8259_Priority_Resolver (
    // Inputs from control logic
    input   logic   [2:0]   priority_rotate,
    input   logic   [7:0]   interrupt_mask,
    input   logic   [7:0]   interrupt_special_mask,
    input   logic           special_fully_nest_config,
    input   logic   [7:0]   highest_level_in_service,

    // Inputs
    input   logic   [7:0]   interrupt_request_register,
    input   logic   [7:0]   in_service_register,

    // Outputs
    output  logic   [7:0]   interrupt
);
    import KF8259_Common_Package::rotate_right;
    import KF8259_Common_Package::rotate_left;
    import KF8259_Common_Package::resolv_priority;

    //
    // Masked flags
    //
    logic   [7:0]   masked_interrupt_request;
    assign masked_interrupt_request = interrupt_request_register & ~interrupt_mask;

    logic   [7:0]   masked_in_service;
    assign masked_in_service        = in_service_register & ~interrupt_special_mask;


    //
    // Resolve priority
    //
    logic   [7:0]   rotated_request;
    logic   [7:0]   rotated_in_service;
    logic   [7:0]   rotated_highest_level_in_service;
    logic   [7:0]   priority_mask;
    logic   [7:0]   rotated_interrupt;

    assign rotated_request = rotate_right(masked_interrupt_request, priority_rotate);

    assign rotated_highest_level_in_service = rotate_right(highest_level_in_service, priority_rotate);

    always_comb begin
        rotated_in_service = rotate_right(masked_in_service, priority_rotate);

        if (special_fully_nest_config == 1'b1)
            rotated_in_service = (rotated_in_service & ~rotated_highest_level_in_service)
                                | {rotated_highest_level_in_service[6:0], 1'b0};
    end

    always_comb begin
        if      (rotated_in_service[0] == 1'b1) priority_mask = 8'b00000000;
        else if (rotated_in_service[1] == 1'b1) priority_mask = 8'b00000001;
        else if (rotated_in_service[2] == 1'b1) priority_mask = 8'b00000011;
        else if (rotated_in_service[3] == 1'b1) priority_mask = 8'b00000111;
        else if (rotated_in_service[4] == 1'b1) priority_mask = 8'b00001111;
        else if (rotated_in_service[5] == 1'b1) priority_mask = 8'b00011111;
        else if (rotated_in_service[6] == 1'b1) priority_mask = 8'b00111111;
        else if (rotated_in_service[7] == 1'b1) priority_mask = 8'b01111111;
        else                                    priority_mask = 8'b11111111;
    end

    assign rotated_interrupt = resolv_priority(rotated_request) & priority_mask;

    assign interrupt = rotate_left(rotated_interrupt, priority_rotate);

endmodule
