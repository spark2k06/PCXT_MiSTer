//
// KFSDRAM
// SDRAM Controller
//
// Written by kitune-san
//
module KFSDRAM #(
    parameter sdram_col_width       = 9,
    parameter sdram_row_width       = 13,
    parameter sdram_bank_width      = 2,
    parameter sdram_data_width      = 16,
    parameter sdram_no_refresh      = 1'b0,
    parameter sdram_trc             = 16'd5-16'd1,
    parameter sdram_trp             = 16'd1-16'd1,
    parameter sdram_tmrd            = 16'd2-16'd1,
    parameter sdram_trcd            = 16'd1-16'd1,
    parameter sdram_tdpl            = 16'd2-16'd1,
    parameter cas_latency           = 3'b010,
    parameter sdram_init_wait       = 16'd10000,
    parameter sdram_refresh_cycle   = 16'd00100,
    parameter sdram_force_refresh   = 16'd00400
) (
    input   logic                               sdram_clock,
    input   logic                               sdram_reset,

    // Control
    input   logic   [sdram_col_width
                    + sdram_row_width
                    + sdram_bank_width-1:0]     address,
    input   logic   [sdram_col_width-1:0]       access_num,
    input   logic   [sdram_data_width-1:0]      data_in,
    output  reg     [sdram_data_width-1:0]      data_out,
    input   logic                               write_request,
    input   logic                               read_request,
    input   logic                               enable_refresh,
    output  logic                               write_flag,
    output  reg                                 read_flag,
    output  logic                               refresh_mode,
    output  logic                               idle,

    // SDRAM
    output  logic   [sdram_row_width-1:0]       sdram_address,
    output  logic                               sdram_cke,
    output  logic                               sdram_cs,
    output  logic                               sdram_ras,
    output  logic                               sdram_cas,
    output  logic                               sdram_we,
    output  logic   [sdram_bank_width-1:0]      sdram_ba,
    input   logic   [sdram_data_width-1:0]      sdram_dq_in,
    output  logic   [sdram_data_width-1:0]      sdram_dq_out,
    output  logic                               sdram_dq_io
);

    `define ROW_ADDRESS_TOP         (sdram_col_width + sdram_row_width - 1)
    `define ROW_ADDRESS_BOTTOM      (sdram_col_width)
    `define BANK_ADDRESS_TOP        (sdram_col_width + sdram_row_width + sdram_bank_width - 1)
    `define BANK_ADDRESS_BOTTOM     (sdram_col_width + sdram_row_width)

    typedef enum { INIT, PALL, INIT_CBR_1, INIT_CBR_2, MRS, REFRESH_PALL, REFRESH, IDLE, WRITE, PRECHARGE_WAIT, READ, PRECHARGE } state_t;

    state_t                             state;
    state_t                             next_state;
    logic   [15:0]                      state_counter;
    logic   [15:0]                      refresh_counter;
    logic   [sdram_col_width-1:0]       access_counter;
    logic   [sdram_col_width-1:0]       read_counter;
    logic                               send_cmd_timing;
    logic                               end_read_cmd;

    //
    // State Machine
    //
    always_comb begin
        next_state = state;

        casez (state)
            INIT: begin
                if (state_counter == sdram_init_wait)
                    next_state = PALL;
            end
            PALL: begin
                if (state_counter == sdram_trp)
                    next_state = INIT_CBR_1;
            end
            INIT_CBR_1: begin
                if (state_counter == sdram_trc)
                    next_state = INIT_CBR_2;
            end
            INIT_CBR_2: begin
                if (state_counter == sdram_trc)
                    next_state = MRS;
            end
            MRS: begin
                if (state_counter == sdram_tmrd)
                    next_state = IDLE;
            end
            REFRESH_PALL: begin
                if (state_counter == sdram_trp)
                    next_state = REFRESH;
            end
            REFRESH: begin
                if (state_counter == sdram_trc)
                    next_state = IDLE;
            end
            IDLE: begin
                if (write_request)
                    next_state = WRITE;
                else if (read_request)
                    next_state = READ;
                else if ((~sdram_no_refresh) && 
                    ((enable_refresh) && (refresh_counter >= sdram_refresh_cycle)) || (refresh_counter == sdram_force_refresh))
                    next_state = REFRESH_PALL;
            end
            WRITE: begin
                if (access_counter == (access_num - 1))
                    next_state = PRECHARGE_WAIT;
            end
            PRECHARGE_WAIT: begin
                if (state_counter == sdram_tdpl)
                    next_state = PRECHARGE;
            end
            READ: begin
                if ((end_read_cmd) && (read_counter == access_num))
                    next_state = PRECHARGE;
            end
            PRECHARGE: begin
                if (state_counter == sdram_trp)
                    next_state = IDLE;
            end
            default: begin
                next_state = INIT;
            end
        endcase
    end

    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            state <= INIT;
        else
            state <= next_state;
    end


    //
    // State Counter
    //
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            state_counter   <= 0;
        else if (next_state != state)
            state_counter   <= 0;
        else
            state_counter   <= state_counter + 16'h01;
    end


    //
    // Reflesh Counter
    //
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            refresh_counter <= 0;
        else if ((~sdram_cs) && (~sdram_ras) & (~sdram_cas) & (sdram_we))
            refresh_counter <= 0;
        else if (refresh_counter != sdram_force_refresh)
            refresh_counter <= refresh_counter + 16'h01;
        else
            refresh_counter <= refresh_counter;
    end


    //
    // Access Counter
    //
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            access_counter  <= 0;
        else if ((state == WRITE) || (state == READ))
            access_counter  <= access_counter + 1;
        else
            access_counter  <= 0;
    end


    //
    // Read Counter
    //
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            read_counter    <= 0;
        else if (state != READ)
            read_counter    <= 0;
        else if (state_counter <= cas_latency)
            read_counter    <= 0;
        else if (read_counter != access_num)
            read_counter    <= read_counter + 1;
        else
            read_counter    <= read_counter;
    end


    //
    // Timing Signals
    //
    assign  send_cmd_timing = state_counter == 0;
    assign  end_read_cmd    = state_counter >= access_num;


    //
    // Output
    //
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset) begin
            sdram_address   <= 0;
            sdram_cke       <= 1'b0;
            sdram_cs        <= 1'b1;
            sdram_ras       <= 1'b1;
            sdram_cas       <= 1'b1;
            sdram_we        <= 1'b1;
            sdram_ba        <= 0;
            sdram_dq_out    <= 0;
            sdram_dq_io     <= 1'b1;
        end
        else begin
            casez (state)
                INIT: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                PALL: begin
                    sdram_address[9:0]  <= 0;
                    sdram_address[10]   <= 1'b1;
                    sdram_address[sdram_row_width-1:11] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                INIT_CBR_1: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                INIT_CBR_2: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                MRS: begin
                    sdram_address[9:0] <= (send_cmd_timing) ? {2'b000, cas_latency, 4'b0000} : 0;
                    sdram_address[sdram_row_width-1:10] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_we        <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                REFRESH_PALL: begin
                    sdram_address[9:0]  <= 0;
                    sdram_address[10]   <= 1'b1;
                    sdram_address[sdram_row_width-1:11] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                REFRESH: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                IDLE : begin
                    if (next_state == WRITE) begin
                        sdram_address   <= address[`ROW_ADDRESS_TOP:`ROW_ADDRESS_BOTTOM];
                        sdram_cke       <= 1'b1;
                        sdram_cs        <= 1'b0;
                        sdram_ras       <= 1'b0;
                        sdram_cas       <= 1'b1;
                        sdram_we        <= 1'b1;
                        sdram_ba        <= address[`BANK_ADDRESS_TOP:`BANK_ADDRESS_BOTTOM];
                        sdram_dq_out    <= 0;
                        sdram_dq_io     <= 1'b1;
                    end
                    else if (next_state == READ) begin
                        sdram_address   <= address[`ROW_ADDRESS_TOP:`ROW_ADDRESS_BOTTOM];
                        sdram_cke       <= 1'b1;
                        sdram_cs        <= 1'b0;
                        sdram_ras       <= 1'b0;
                        sdram_cas       <= 1'b1;
                        sdram_we        <= 1'b1;
                        sdram_ba        <= address[`BANK_ADDRESS_TOP:`BANK_ADDRESS_BOTTOM];
                        sdram_dq_out    <= 0;
                        sdram_dq_io     <= 1'b1;
                    end
                    else begin
                        sdram_address   <= 0;
                        sdram_cke       <= 1'b1;
                        sdram_cs        <= 1'b0;
                        sdram_ras       <= 1'b1;
                        sdram_cas       <= 1'b1;
                        sdram_we        <= 1'b1;
                        sdram_ba        <= 0;
                        sdram_dq_out    <= 0;
                        sdram_dq_io     <= 1'b1;
                    end
                end
                WRITE: begin
                    sdram_address[sdram_col_width-1:0]  <= address[sdram_col_width-1:0] + access_counter;
                    sdram_address[sdram_row_width-1:sdram_col_width] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= 1'b1;
                    sdram_cas       <= 1'b0;
                    sdram_we        <= 1'b0;
                    sdram_ba        <= address[`BANK_ADDRESS_TOP:`BANK_ADDRESS_BOTTOM];
                    sdram_dq_out    <= data_in;
                    sdram_dq_io     <= 1'b0;
                end
                PRECHARGE_WAIT: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                READ: begin
                    sdram_address[sdram_col_width-1:0]  <= (~end_read_cmd) ? address[sdram_col_width-1:0] + access_counter : 0;
                    sdram_address[sdram_row_width-1:sdram_col_width] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= 1'b1;
                    sdram_cas       <= (~end_read_cmd) ? 1'b0 : 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= (~end_read_cmd) ? address[`BANK_ADDRESS_TOP:`BANK_ADDRESS_BOTTOM] : 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                PRECHARGE: begin
                    sdram_address[9:0]  <= 0;
                    sdram_address[10]   <= 1'b1;
                    sdram_address[sdram_row_width-1:11] <= 0;
                    sdram_cke       <= 1'b1;
                    sdram_cs        <= 1'b0;
                    sdram_ras       <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= (send_cmd_timing) ? 1'b0 : 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
                default: begin
                    sdram_address   <= 0;
                    sdram_cke       <= 1'b0;
                    sdram_cs        <= 1'b1;
                    sdram_ras       <= 1'b1;
                    sdram_cas       <= 1'b1;
                    sdram_we        <= 1'b1;
                    sdram_ba        <= 0;
                    sdram_dq_out    <= 0;
                    sdram_dq_io     <= 1'b1;
                end
            endcase
        end
    end


    //
    // Status
    //
    assign  idle            = (state == IDLE);
    assign  refresh_mode    = (state == REFRESH_PALL) || (state == REFRESH);
    assign  write_flag      = (state == WRITE);
    wire    read_flag_comb  = (state == READ) && (next_state == READ)  && (state_counter > cas_latency);

    //
    // Input Data
    //
    always_ff @(posedge sdram_clock) begin
		data_out <= sdram_dq_in;
		read_flag <= read_flag_comb;
    end



endmodule
