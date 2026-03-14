//
// XT_CE_Generator
//
// Generate the virtual 8088 CLK pin plus synchronous clock-enable pulses for
// the XT/chipset domain from the single 50 MHz chipset clock.
//
module XT_CE_Generator (
    input   logic           clock,
    input   logic           reset,
    input   logic           clk_select_load,
    input   logic   [1:0]   clk_select,

    output  logic           cpu_clk_pin,
    output  logic           cpu_ce_posedge,
    output  logic           cpu_ce_negedge,
    output  logic           peripheral_ce,

    output  logic           cycle_accrate,
    output  logic   [7:0]   clock_cycle_counter_division_ratio,
    output  logic   [7:0]   clock_cycle_counter_decrement_value,
    output  logic           shift_read_timing,
    output  logic   [1:0]   ram_read_wait_cycle,
    output  logic   [1:0]   ram_write_wait_cycle
);

    localparam logic [8:0] PERIPHERAL_CE_NUM = 9'd21;
    localparam logic [8:0] PERIPHERAL_CE_DEN = 9'd440;

    logic   [1:0]   active_clk_select;
    logic   [8:0]   cpu_phase_acc;
    logic   [8:0]   peripheral_phase_acc;
    logic   [8:0]   cpu_edge_num;
    logic   [8:0]   cpu_edge_den;
    logic   [9:0]   cpu_phase_sum;
    logic   [9:0]   peripheral_phase_sum;

    wire speed_change = clk_select_load && (clk_select != active_clk_select);

    always_comb
    begin
        cpu_phase_sum = {1'b0, cpu_phase_acc} + {1'b0, cpu_edge_num};
        peripheral_phase_sum = {1'b0, peripheral_phase_acc} + {1'b0, PERIPHERAL_CE_NUM};

        cycle_accrate = 1'b1;
        clock_cycle_counter_division_ratio = 8'd0;
        clock_cycle_counter_decrement_value = 8'd1;
        shift_read_timing = 1'b0;
        ram_read_wait_cycle = 2'd0;
        ram_write_wait_cycle = 2'd0;
        cpu_edge_num = 9'd21;
        cpu_edge_den = 9'd110;

        case (active_clk_select)
            2'b00:
            begin
                cpu_edge_num = 9'd21;
                cpu_edge_den = 9'd110;
            end

            2'b01:
            begin
                cpu_edge_num = 9'd63;
                cpu_edge_den = 9'd220;
                clock_cycle_counter_division_ratio = 8'd2 - 8'd1;
                clock_cycle_counter_decrement_value = 8'd3;
            end

            2'b10:
            begin
                cpu_edge_num = 9'd21;
                cpu_edge_den = 9'd55;
                clock_cycle_counter_division_ratio = 8'd10 - 8'd1;
                clock_cycle_counter_decrement_value = 8'd21;
            end

            2'b11:
            begin
                cpu_edge_num = 9'd1;
                cpu_edge_den = 9'd1;
                cycle_accrate = 1'b0;
                clock_cycle_counter_decrement_value = 8'd5;
                shift_read_timing = 1'b1;
                ram_read_wait_cycle = 2'd1;
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            active_clk_select <= 2'b00;
            cpu_phase_acc <= 9'd0;
            peripheral_phase_acc <= 9'd0;
            cpu_clk_pin <= 1'b0;
            cpu_ce_posedge <= 1'b0;
            cpu_ce_negedge <= 1'b0;
            peripheral_ce <= 1'b0;
        end
        else
        begin
            cpu_ce_posedge <= 1'b0;
            cpu_ce_negedge <= 1'b0;
            peripheral_ce <= 1'b0;

            if (speed_change)
            begin
                active_clk_select <= clk_select;
                cpu_phase_acc <= 9'd0;
            end
            else if (cpu_phase_sum >= {1'b0, cpu_edge_den})
            begin
                cpu_phase_acc <= cpu_phase_sum[8:0] - cpu_edge_den;
                if (cpu_clk_pin)
                    cpu_ce_negedge <= 1'b1;
                else
                    cpu_ce_posedge <= 1'b1;

                cpu_clk_pin <= ~cpu_clk_pin;
            end
            else
                cpu_phase_acc <= cpu_phase_sum[8:0];

            if (peripheral_phase_sum >= {1'b0, PERIPHERAL_CE_DEN})
            begin
                peripheral_phase_acc <= peripheral_phase_sum[8:0] - PERIPHERAL_CE_DEN;
                peripheral_ce <= 1'b1;
            end
            else
                peripheral_phase_acc <= peripheral_phase_sum[8:0];
        end
    end

endmodule