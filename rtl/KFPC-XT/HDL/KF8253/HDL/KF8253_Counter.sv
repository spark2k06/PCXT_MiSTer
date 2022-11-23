//
// KF8253_Counter
// Counter Logic
//
// Written by Kitune-san
//

`include "KF8253_Definitions.svh"

module KF8253_Counter (
    // Bus
    input   logic           clock,
    input   logic           reset,

    input   logic   [7:0]   internal_data_bus,
    input   logic           write_control,
    input   logic           write_counter,
    input   logic           read_counter,

    output  logic   [7:0]   read_counter_data,

    // I/O
    input   logic           counter_clock,
    input   logic           counter_gate,
    output  logic           counter_out
);

    //
    // Internal Signals
    //
    logic   [1:0]   select_read_write;
    logic           update_counter_config;
    logic           update_select_read_write;
    logic           count_latched_flag;
    logic   [2:0]   select_mode;
    logic           select_bcd;

    logic           write_count_step;
    logic   [15:0]  count_preset;
    logic   [16:0]  count_preset_load;

    logic           read_negedge;
    logic           read_count_step;
    logic           prev_read_counter;

    logic           prev_counter_clock;
    logic           count_edge;

    logic           prev_counter_gate;
    logic           gate_edge;

    logic           load_edge;

    logic           start_counting;

    logic           first_count_edge;

    logic   [16:0]  count_next;
    logic           count_period;
    logic           prev_count_period;

    logic   [16:0]  count;
    logic   [16:0]  count_latched;


    //
    // Mode control word
    //
    // READ/LOAD
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            select_read_write  <= `RL_SELECT_MSB;
        end
        else if (write_control) begin
            case (internal_data_bus[5:4])
                `RL_SELECT_MSB     : begin
                    select_read_write  <= internal_data_bus[5:4];
                end
                `RL_SELECT_LSB     : begin
                    select_read_write  <= internal_data_bus[5:4];
                end
                `RL_SELECT_LSB_MSB : begin
                    select_read_write  <= internal_data_bus[5:4];
                end
                default         : begin
                    select_read_write  <= select_read_write;
                end
            endcase
        end
        else begin
            select_read_write  <= select_read_write;
        end
    end

    assign update_counter_config = (internal_data_bus[5:4] != `RL_COUNTER_LATCH) & write_control;
    assign update_select_read_write = (select_read_write != internal_data_bus[5:4]) & update_counter_config;

    // Read latch
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            count_latched_flag <= 1'b0;
        else if ((write_control) && (internal_data_bus[5:4] == `RL_COUNTER_LATCH))
            count_latched_flag <= 1'b1;
        else if ((count_latched_flag == 1'b1) && (read_negedge)) begin
            if (select_read_write != `RL_SELECT_LSB_MSB)
                count_latched_flag <= 1'b0;
            else
                count_latched_flag <= (read_count_step == 1'b0) ? 1'b0 : 1'b1;
        end
        else
            count_latched_flag <= count_latched_flag;
    end

    // MODE
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            select_mode <= `KF8253_CONTROL_MODE_0;
        else if (update_counter_config)
            select_mode <= internal_data_bus[3:1];
        else
            select_mode <= select_mode;
    end

    // BCD
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            select_bcd <= 1'b0;
        else if (update_counter_config)
            select_bcd <= internal_data_bus[0];
        else
            select_bcd <= select_bcd;
    end


    //
    // Write count value (preset)
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            count_preset[15:0] <= 16'h0000;
        else if (write_counter)
            if (write_count_step == 1'b0)
                count_preset[15:0] <= {internal_data_bus,  count_preset[7:0]};
            else
                count_preset[15:0] <= {count_preset[15:8], internal_data_bus};
        else
            count_preset[15:0] <= count_preset[15:0];
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_count_step <= 1'b0;
        else if (update_select_read_write)
            case (internal_data_bus[5:4])
                `RL_SELECT_MSB      : write_count_step <= 1'b0;
                `RL_SELECT_LSB      : write_count_step <= 1'b1;
                `RL_SELECT_LSB_MSB  : write_count_step <= 1'b1;
                default             : write_count_step <= write_count_step;
            endcase
        else if ((write_counter) && (select_read_write == `RL_SELECT_LSB_MSB))
            write_count_step <= (write_count_step) ? 1'b0 : 1'b1;
        else
            write_count_step <= write_count_step;
    end

    always_comb begin
        count_preset_load[15:0] = (select_read_write == `RL_SELECT_MSB) ? {count_preset[15:8], 8'h00} :
                                  (select_read_write == `RL_SELECT_LSB) ? {8'h00, count_preset[ 7:0]} :
                                                                          count_preset[15:0];
        count_preset_load[16]   = (count_preset_load[15:0] == 16'h0000) ? 1'b1 : 1'b0;
    end


    //
    // Read count value (latched)
    //
    always_comb begin
        if (read_count_step == 1'b0)
            read_counter_data <= count_latched[15:8];
        else
            read_counter_data <= count_latched[7:0];
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_read_counter <= 1'b0;
        else
            prev_read_counter <= read_counter;
    end

    assign read_negedge = ((prev_read_counter != read_counter) & read_counter == 1'b0);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_count_step <= 1'b0;
        else if (update_select_read_write)
            case (internal_data_bus[5:4])
                `RL_SELECT_MSB      : read_count_step <= 1'b0;
                `RL_SELECT_LSB      : read_count_step <= 1'b1;
                `RL_SELECT_LSB_MSB  : read_count_step <= 1'b1;
                default             : read_count_step <= read_count_step;
            endcase
        else if ((read_negedge) && (select_read_write == `RL_SELECT_LSB_MSB))
            read_count_step <= (read_count_step) ? 1'b0 : 1'b1;
        else
            read_count_step <= read_count_step;
    end


    //
    // Count Counter
    //
    // Count trigger
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_counter_clock <= 1'b0;
        else
            prev_counter_clock <= counter_clock;
    end

    assign count_edge = (prev_counter_clock != counter_clock) & (counter_clock == 1'b0);

    // Gate trigger
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_counter_gate <= 1'b0;
        else if (count_edge)
            prev_counter_gate <= counter_gate;
        else
            if (prev_counter_gate != 1'b0)
                prev_counter_gate <= counter_gate;
            else
                prev_counter_gate <= prev_counter_gate;
    end

    assign gate_edge = (prev_counter_gate != counter_gate) & (counter_gate == 1'b1);

    // Load trigger
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            load_edge <= 1'b0;
        else if (write_counter)
            load_edge <= 1'b1;
        else if (count_edge)
            load_edge <= 1'b0;
        else
            load_edge <= load_edge;
    end

    // Count start/end
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            start_counting <= 1'b0;
        else if (update_counter_config)
            start_counting <= 1'b0;
        else if (write_counter) begin
            if (select_read_write != `RL_SELECT_LSB_MSB)
                start_counting <= 1'b1;
            else begin
                casez (select_mode)
                    `KF8253_CONTROL_MODE_0: begin
                        if (write_count_step == 1'b0)
                            start_counting <= 1'b1;
                        else
                            start_counting <= 1'b0;
                    end
                    `KF8253_CONTROL_MODE_4: begin
                        if (write_count_step == 1'b0)
                            start_counting <= 1'b1;
                        else
                            start_counting <= 1'b0;
                    end
                    default        : begin
                        if (start_counting == 1'b1)
                            start_counting <= 1'b1;
                        else begin
                            if (write_count_step == 1'b0)
                                start_counting <= 1'b1;
                            else
                                start_counting <= 1'b0;
                        end
                    end
                endcase
            end
        end
        else
            start_counting <= start_counting;
    end

    // First counte edge signal
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            first_count_edge    <= 1'b0;
        else if (start_counting==1'b0)
            first_count_edge    <= 1'b1;
        else if (count_edge == 1'b1)
            first_count_edge    <= 1'b0;
        else
            first_count_edge    <= first_count_edge;
    end

    // Decrement counter
    function logic [16:0] decrement (input [16:0] count, input is_bcd);
        if (count == 17'b0_0000_0000_0000_0000)
            decrement = 17'b0_0000_0000_0000_0000;
        else
            if (is_bcd == 1'b0)
                decrement = count - 17'b0_0000_0000_0000_0001;
            else begin
                if (count[3:0] == 4'b0000) begin
                    if (count[7:4] == 4'b0000) begin
                        if (count[11:8] == 4'b0000) begin
                            if (count[15:12] == 4'b0000) begin
                                decrement[16]    = 1'b0;
                                decrement[15:12] = 4'd9;
                            end
                            else begin
                                decrement[16]    = count[16];
                                decrement[15:12] = count[15:12] - 4'd1;
                            end
                            decrement[11:8]  = 4'd9;
                        end
                        else begin
                            decrement[16:12] = count[16:12];
                            decrement[11:8]  = count[11:8]  - 4'd1;
                        end
                        decrement[7:4]  = 4'd9;
                    end
                    else begin
                        decrement[16:8] = count[16:8];
                        decrement[7:4]  = count[7:4] - 4'd1;
                    end
                    decrement[3:0]  = 4'd9;
                end
                else begin
                    decrement[16:4] = count[16:4];
                    decrement[3:0]  = count[3:0] - 4'd1;
                end
            end
    endfunction

    // Generate next count value.
    logic   [16:0]  dec_count;
    logic   [16:0]  dec2_count;
    assign dec_count  = decrement(count, select_bcd);
    assign dec2_count = decrement(dec_count, select_bcd);

    always_comb begin
        count_next = dec_count;
        count_period = 1'b0;

        casez (select_mode)
            `KF8253_CONTROL_MODE_0: begin
                if (counter_gate == 1'b0)
                    count_next = count;

                if (load_edge)
                    count_next = count_preset_load;
            end

            `KF8253_CONTROL_MODE_1: begin
                if (gate_edge)
                    count_next = count_preset_load;
            end

            `KF8253_CONTROL_MODE_2: begin
                if (counter_gate == 1'b0)
                    count_next = count;

                if (count_next == 16'h00)
                    count_next = count_preset_load;

                if (gate_edge)
                    count_next = count_preset_load;
            end

            `KF8253_CONTROL_MODE_3: begin
                if (count[0] == 1'b1) begin
                    if (counter_out == 1'b0)
                        count_next = {dec2_count[16:1], 1'b0};
                end
                else
                    count_next = dec2_count;

                if (counter_gate == 1'b0)
                    count_next = count;

                if (count_next == 17'b0_0000_0000_0000_0000) begin
                    count_period = 1'b1 & ~first_count_edge;
                    count_next = count_preset_load;
                end

                if (gate_edge)
                    count_next = count_preset_load;
            end

            `KF8253_CONTROL_MODE_4: begin
                if (counter_gate == 1'b0)
                    count_next = count;

                if (load_edge)
                    count_next = count_preset_load;
            end

            `KF8253_CONTROL_MODE_5: begin
                if (gate_edge)
                    count_next = count_preset_load;
            end
            default: begin
            end
        endcase

        if (count_next == 17'b0_0000_0000_0000_0000)
            count_period = 1'b1;
    end

    // Update Count
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            count <= 17'b0_0000_0000_0000_0000;
            count_latched <= 17'b0_0000_0000_0000_0000;
        end
        else if (start_counting == 1'b0) begin
            count <= 17'b0_0000_0000_0000_0000;
            if (count_latched_flag == 1'b0)
                count_latched <= 17'b0_0000_0000_0000_0000;
            else
                count_latched <= count_latched;
        end
        else if (start_counting & count_edge) begin
            count <= count_next;
            if (count_latched_flag == 1'b0)
                count_latched <= count_next;
            else
                count_latched <= count_latched;
        end
        else begin
            count <= count;
            if (count_latched_flag == 1'b0)
                count_latched <= count;
            else
                count_latched <= count_latched;
        end
    end

    // Period
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_count_period <= 1'b1;
        else if (start_counting == 1'b0)
            prev_count_period <= 1'b1;
        else if (count_edge)
            prev_count_period <= count_period;
        else
            prev_count_period <= prev_count_period;
    end

    // Output
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            counter_out <= 1'b0;
        else if (start_counting == 1'b0) begin
            casez (select_mode)
                `KF8253_CONTROL_MODE_0: counter_out <= 1'b0;
                `KF8253_CONTROL_MODE_1: counter_out <= 1'b1;
                `KF8253_CONTROL_MODE_2: counter_out <= 1'b1;
                `KF8253_CONTROL_MODE_3: counter_out <= 1'b1;
                `KF8253_CONTROL_MODE_4: counter_out <= 1'b1;
                `KF8253_CONTROL_MODE_5: counter_out <= 1'b1;
                default        : counter_out <= 1'b0;
            endcase
        end
        else if (count_edge) begin
            casez (select_mode)
                `KF8253_CONTROL_MODE_0: begin
                    if (count_period)
                        counter_out <= 1'b1;
                    else
                        counter_out <= 1'b0;
                end
                `KF8253_CONTROL_MODE_1: begin
                    if (count_period)
                        counter_out <= 1'b1;
                    else
                        counter_out <= 1'b0;
                end
                `KF8253_CONTROL_MODE_2: begin
                    if (counter_gate == 1'b0)
                        counter_out <= 1'b1;
                    else if (count_next == 17'b0_0000_0000_0000_0001)
                        counter_out <= 1'b0;
                    else
                        counter_out <= 1'b1;
                end
                `KF8253_CONTROL_MODE_3: begin
                    if (counter_gate == 1'b0)
                        counter_out <= 1'b1;
                    else if (count_period)
                        counter_out <= ~counter_out;
                    else
                        counter_out <= counter_out;
                end
                `KF8253_CONTROL_MODE_4: begin
                    if ((count_period) && (prev_count_period == 1'b0))
                        counter_out <= 1'b0;
                    else
                        counter_out <= 1'b1;
                end
                `KF8253_CONTROL_MODE_5: begin
                    if ((count_period) && (prev_count_period == 1'b0))
                        counter_out <= 1'b0;
                    else
                        counter_out <= 1'b1;
                end
                default        : begin
                    counter_out <= counter_out;
                end
            endcase
        end
        else
            casez (select_mode)
                `KF8253_CONTROL_MODE_2: begin
                    if ((counter_gate == 1'b0) || (prev_counter_gate == 1'b0))
                        counter_out <= 1'b1;
                    else
                        counter_out <= counter_out;
                end
                `KF8253_CONTROL_MODE_3: begin
                    if ((counter_gate == 1'b0) || (prev_counter_gate == 1'b0))
                        counter_out <= 1'b1;
                    else
                        counter_out <= counter_out;
                end
                default:
                    counter_out <= counter_out;
            endcase
    end
endmodule

