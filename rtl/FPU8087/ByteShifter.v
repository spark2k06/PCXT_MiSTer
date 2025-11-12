// Copyright 2025, Waldo Alvarez, https://pipflow.com

//Implementing a byte shifter in a similar multiplexer-based approach as the bit shifter involves selecting one of eight 8-bit segments (or "bytes") from the 64-bit input, based on the shift amount. This design is somewhat simpler than the bit shifter, as the shift operations are in 8-bit increments (1 byte), reducing the complexity of the multiplexers.

//Here's an example implementation for a 64-bit multiplexer-based byte shifter:


module multiplexer_based_byte_shifter_left(
    input [63:0] data_in,
    input [2:0] byte_shift,  // 3 bits for 0-7 byte shifts
    output reg [63:0] data_out  // Declare as reg
);

    // Define wires for each byte segment
    wire [63:0] shifted_bytes[7:0];

    // Assign shifted byte segments
    assign shifted_bytes[0] = data_in;                 // No shift
    assign shifted_bytes[1] = {data_in[55:0], 8'd0};   // Shift by 1 byte
    assign shifted_bytes[2] = {data_in[47:0], 16'd0};  // Shift by 2 bytes
    assign shifted_bytes[3] = {data_in[39:0], 24'd0};  // Shift by 3 bytes
    assign shifted_bytes[4] = {data_in[31:0], 32'd0};  // Shift by 4 bytes
    assign shifted_bytes[5] = {data_in[23:0], 40'd0};  // Shift by 5 bytes
    assign shifted_bytes[6] = {data_in[15:0], 48'd0};  // Shift by 6 bytes
    assign shifted_bytes[7] = {data_in[7:0],  56'd0};  // Shift by 7 bytes

    // Use a case statement to select the correct output
    always @(*) begin
        case (byte_shift)
            3'b000: data_out = shifted_bytes[0];
            3'b001: data_out = shifted_bytes[1];
            3'b010: data_out = shifted_bytes[2];
            3'b011: data_out = shifted_bytes[3];
            3'b100: data_out = shifted_bytes[4];
            3'b101: data_out = shifted_bytes[5];
            3'b110: data_out = shifted_bytes[6];
            3'b111: data_out = shifted_bytes[7];
        endcase
    end

endmodule



module multiplexer_based_byte_shifter_right(
    input [63:0] data_in,
    input [2:0] byte_shift,  // 3 bits for 0-7 byte shifts
    output reg [63:0] data_out
);

    // Define wires for each byte segment
    wire [63:0] shifted_bytes[7:0];

    // Assign shifted byte segments for right shift
    assign shifted_bytes[0] = data_in;                 // No shift
    assign shifted_bytes[1] = {8'd0, data_in[63:8]};   // Shift by 1 byte
    assign shifted_bytes[2] = {16'd0, data_in[63:16]}; // Shift by 2 bytes
    assign shifted_bytes[3] = {24'd0, data_in[63:24]}; // Shift by 3 bytes
    assign shifted_bytes[4] = {32'd0, data_in[63:32]}; // Shift by 4 bytes
    assign shifted_bytes[5] = {40'd0, data_in[63:40]}; // Shift by 5 bytes
    assign shifted_bytes[6] = {48'd0, data_in[63:48]}; // Shift by 6 bytes
    assign shifted_bytes[7] = {56'd0, data_in[63:56]}; // Shift by 7 bytes

    // Use a case statement to select the correct output
    always @(*) begin
        case (byte_shift)
            3'b000: data_out = shifted_bytes[0];
            3'b001: data_out = shifted_bytes[1];
            3'b010: data_out = shifted_bytes[2];
            3'b011: data_out = shifted_bytes[3];
            3'b100: data_out = shifted_bytes[4];
            3'b101: data_out = shifted_bytes[5];
            3'b110: data_out = shifted_bytes[6];
            3'b111: data_out = shifted_bytes[7];
        endcase
    end

endmodule
