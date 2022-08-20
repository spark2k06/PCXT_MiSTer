//
// KFPS2KB_Send_Data
//
// Written by kitune-san
//
module KFPS2KB_Send_Data #(
    parameter device_out_clock_wait = 16'd240
) (
    input   logic           clock,
    input   logic           peripheral_clock,
    input   logic           reset,

    input   logic           device_clock,
    output  logic           device_clock_out,
    output  logic           device_data_out,
    output  logic           sending_data_flag,

    input   logic           send_request,
    input   logic   [7:0]   send_data
);

    // State
    typedef enum {READY, CLKLOW, STARTBIT, SEND, STOPBIT, LAST} shit_state_t;

    //
    // Internal Signals
    //
    logic           prev_device_clock;
    logic           device_clock_edge;
    logic           prev_send_request;
    logic           send_request_trigger;
    logic   [9:0]   shift_register;
    logic   [7:0]   parity_bit;

    shit_state_t    state;
    shit_state_t    next_state;
    logic   [15:0]  state_counter;
    logic   [7:0]   send_bit_count;


    //
    // Detect peripheral clock edge
    //
    logic           prev_p_clock_1;
    logic           prev_p_clock_2;
    logic           device_clock_last_edge;

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
    assign device_clock_last_edge = (prev_device_clock != device_clock) & (device_clock == 1'b1);


    //
    // Detect send request edge
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_send_request <= 1'b0;
        else
            prev_send_request <= send_request;
    end

    assign  send_request_trigger = ~prev_send_request & send_request;


    //
    // Shift register
    //
    assign parity_bit = ~(send_data[0]
                        + send_data[1]
                        + send_data[2]
                        + send_data[3]
                        + send_data[4]
                        + send_data[5]
                        + send_data[6]
                        + send_data[7]);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            shift_register <= 10'b11_1111_1111;
        else if (send_request_trigger)
            shift_register <= {parity_bit ,send_data, 1'b0};
        else if ((state == SEND) && (device_clock_edge))
            shift_register <= {1'b1, shift_register[9:1]};
        else
            shift_register <= shift_register;
    end


    //
    // State Machine
    //
    always_comb begin
        next_state = state;

        case (state)
            READY: begin
                if (send_request_trigger)
                    next_state = CLKLOW;
            end
            CLKLOW: begin
                if (state_counter == device_out_clock_wait)
                    next_state = STARTBIT;
            end
            STARTBIT: begin
                if (state_counter == device_out_clock_wait)
                    next_state = SEND;
            end
            SEND: begin
                if (send_bit_count == 8'd10)
                    next_state = STOPBIT;
            end
            STOPBIT: begin
                if (device_clock_edge)
                    next_state = LAST;
            end
            LAST: begin
                if (device_clock_last_edge)
                    next_state = READY;
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state <= READY;
        else
            state <= next_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state_counter <= 16'h00;
        else if (state != next_state)
            state_counter <= 16'h00;
        else if (p_clock_posedge)
            state_counter <= state_counter + 16'h01;
        else
            state_counter <= state_counter;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            send_bit_count <= 8'h00;
        else if (state == SEND)
            if (device_clock_edge)
                send_bit_count <= send_bit_count + 8'h01;
            else
                send_bit_count <= send_bit_count;
        else
            send_bit_count <= 8'h00;
    end


    //
    // Output
    //
    // device_clock_out
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            device_clock_out <= 1'b1;
        else if ((state == CLKLOW) || (state == STARTBIT))
            device_clock_out <= 1'b0;
        else
            device_clock_out <= 1'b1;
    end

    // device_data_out
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            device_data_out <= 1'b1;
        else if (state == STARTBIT)
            device_data_out <= 1'b0;
        else if (state == SEND)
            device_data_out <= shift_register[0];
        else
            device_data_out <= 1'b1;
    end

    assign  sending_data_flag = (state != READY);

endmodule
