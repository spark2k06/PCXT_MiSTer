// Copyright 2025, Waldo Alvarez, https://pipflow.com
module multiplexer_based_bit_shifter_right(
    input [63:0] data_in,
    input [2:0] shift_amount,  // 3 bits for 0-7 bit shifts
    output reg [63:0] data_out
);

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : bit_shift
            wire [7:0] possible_outputs;

            // Right shift connections
            assign possible_outputs[0] = (i >= 0) ? data_in[i] : 1'b0;
            assign possible_outputs[1] = (i >= 1) ? data_in[i - 1] : 1'b0;
            assign possible_outputs[2] = (i >= 2) ? data_in[i - 2] : 1'b0;
            assign possible_outputs[3] = (i >= 3) ? data_in[i - 3] : 1'b0;
            assign possible_outputs[4] = (i >= 4) ? data_in[i - 4] : 1'b0;
            assign possible_outputs[5] = (i >= 5) ? data_in[i - 5] : 1'b0;
            assign possible_outputs[6] = (i >= 6) ? data_in[i - 6] : 1'b0;
            assign possible_outputs[7] = (i >= 7) ? data_in[i - 7] : 1'b0;

            // Select the output based on shift amount
            always @(*) begin
                case (shift_amount)
                    3'b000: data_out[i] = possible_outputs[0];
                    3'b001: data_out[i] = possible_outputs[1];
                    3'b010: data_out[i] = possible_outputs[2];
                    3'b011: data_out[i] = possible_outputs[3];
                    3'b100: data_out[i] = possible_outputs[4];
                    3'b101: data_out[i] = possible_outputs[5];
                    3'b110: data_out[i] = possible_outputs[6];
                    3'b111: data_out[i] = possible_outputs[7];
                endcase
            end
        end
    endgenerate

endmodule

module multiplexer_based_bit_shifter_left(
    input [63:0] data_in,
    input [2:0] shift_amount,  // 3 bits for 0-7 bit shifts
    output reg [63:0] data_out
);

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : bit_shift
            wire [7:0] possible_outputs;

            // Left shift connections
            assign possible_outputs[0] = (i < 64) ? data_in[i] : 1'b0;
            assign possible_outputs[1] = (i < 63) ? data_in[i + 1] : 1'b0;
            assign possible_outputs[2] = (i < 62) ? data_in[i + 2] : 1'b0;
            assign possible_outputs[3] = (i < 61) ? data_in[i + 3] : 1'b0;
            assign possible_outputs[4] = (i < 60) ? data_in[i + 4] : 1'b0;
            assign possible_outputs[5] = (i < 59) ? data_in[i + 5] : 1'b0;
            assign possible_outputs[6] = (i < 58) ? data_in[i + 6] : 1'b0;
            assign possible_outputs[7] = (i < 57) ? data_in[i + 7] : 1'b0;

            // Select the output based on shift amount
            always @(*) begin
                case (shift_amount)
                    3'b000: data_out[i] = possible_outputs[0];
                    3'b001: data_out[i] = possible_outputs[1];
                    3'b010: data_out[i] = possible_outputs[2];
                    3'b011: data_out[i] = possible_outputs[3];
                    3'b100: data_out[i] = possible_outputs[4];
                    3'b101: data_out[i] = possible_outputs[5];
                    3'b110: data_out[i] = possible_outputs[6];
                    3'b111: data_out[i] = possible_outputs[7];
                endcase
            end
        end
    endgenerate

endmodule

