//
// KFPS2KB_Shift_Register.sv
// PS/2 shift register
//
// Written by kitune-san
//
module KFPS2KB_Shift_Register #(
    parameter over_time = 16'd1000
) (
    input   logic           clock,
    input   logic           peripheral_clock,
    input   logic           reset,

    input   logic           device_clock,
    input   logic           device_data,

    output  logic   [7:0]   register,
    output  logic           recieved_flag,
    output  logic           error_flag
);
    // State
    typedef enum {READY, RECEIVING, STOPBIT} shit_state_t;


    //
    // Internal Signals
    //
    logic           prev_device_clock;
    logic           device_clock_edge;

    logic   [8:0]   shift_register;
    logic   [3:0]   bit_count;
    logic           parity_bit;

    logic   [15:0]  receiving_time;
    logic           over_receiving_time;

    shit_state_t    next_state;
    shit_state_t    state;


    //
    // Detect peripheral clock edge
    //
    logic           prev_p_clock_1;
    logic           prev_p_clock_2;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_p_clock_1 <= 1'b0;
            prev_p_clock_2 <= 1'b0;
        end
        else begin
            prev_p_clock_1 <= peripheral_clock;
            prev_p_clock_2 <= prev_p_clock_1;

        end
    end

    wire    p_clock_posedge = prev_p_clock_1 & ~prev_p_clock_2;


    //
    // Detect clock edge
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_device_clock <= 1'b0;
        else
            prev_device_clock <= device_clock;
    end

    assign device_clock_edge = (prev_device_clock != device_clock) & (device_clock == 1'b0);


    //
    // Shift register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            shift_register <= 9'b0_0000_0000;
        else if ((state == RECEIVING) & (device_clock_edge))
            shift_register <= {device_data, shift_register[8:1]};
        else
            shift_register <= shift_register;
    end


    //
    // Bit Count
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            bit_count <= 4'b0000;
        else if (state == READY)
            bit_count <= 4'b0000;
        else if ((state == RECEIVING) & (device_clock_edge))
            bit_count <= bit_count + 4'b0001;
        else
            bit_count <= bit_count;
    end

    assign parity_bit = ~(shift_register[0]
                        + shift_register[1]
                        + shift_register[2]
                        + shift_register[3]
                        + shift_register[4]
                        + shift_register[5]
                        + shift_register[6]
                        + shift_register[7]);


    //
    // Count receiving time
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            receiving_time <= 16'h0000;
        else if (state == READY)
            receiving_time <= 16'h0000;
        else if (device_clock_edge)
            receiving_time <= 16'h0000;
        else if ((p_clock_posedge) && (over_receiving_time == 1'b0))
            receiving_time <= receiving_time + 16'h0001;
        else
            receiving_time <= receiving_time;
    end

    assign over_receiving_time = (receiving_time >= over_time) ? 1'b1 : 1'b0;


    //
    // Recieved flag and error flag
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            recieved_flag <= 1'b0;
            error_flag    <= 1'b0;
        end
        else if (over_receiving_time) begin
            recieved_flag <= 1'b0;
            error_flag    <= 1'b1;
        end
        else if (state == STOPBIT) begin
            if (device_clock_edge) begin
                if ((device_data == 1'b1) && (shift_register[8] == parity_bit)) begin
                    recieved_flag <= 1'b1;
                    error_flag    <= 1'b0;
                end
                else begin
                    recieved_flag <= 1'b0;
                    error_flag    <= 1'b1;
                end
            end
            else begin
                recieved_flag <= 1'b0;
                error_flag    <= 1'b0;
            end
        end
        else begin
            recieved_flag <= 1'b0;
            error_flag    <= 1'b0;
        end
    end


    //
    // Set register
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            register <= 8'h00;
        else if ((state == STOPBIT) && (device_clock_edge))
            register <= shift_register[7:0];
        else
            register <= register;
    end


    //
    // State Machine
    //
    always_comb begin
        next_state = READY;

        case (state)
            READY: begin
                if ((device_clock_edge) && (device_data == 1'b0))
                    next_state = RECEIVING;
                else
                    next_state = READY;
            end
            RECEIVING: begin
                if (bit_count >= 4'b1001)
                    next_state = STOPBIT;
                else
                    next_state = RECEIVING;
            end
            STOPBIT: begin
                if (device_clock_edge)
                    next_state = READY;
                else
                    next_state = STOPBIT;
            end
        endcase

        if (over_receiving_time)
            next_state = READY;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state <= READY;
        else
            state <= next_state;
    end

endmodule

