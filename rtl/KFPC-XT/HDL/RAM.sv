//
// KFPC-XT Peripherals
// Written by kitune-san
//
module RAM (
    input   logic           clock,
    input   logic           sdram_clock,
    input   logic           reset,
    input   logic           enable_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    output  logic           memory_access_ready,
    output  logic           ram_address_select_n,
    // VRAM FIFO
    // TODO:
    // SDRAM
    output  logic   [12:0]  sdram_address,
    output  logic           sdram_cke,
    output  logic           sdram_cs,
    output  logic           sdram_ras,
    output  logic           sdram_cas,
    output  logic           sdram_we,
    output  logic   [1:0]   sdram_ba,
    input   logic   [15:0]  sdram_dq_in,
    output  logic   [15:0]  sdram_dq_out,
    output  logic           sdram_dq_io,
    output  logic           sdram_ldqm,
    output  logic           sdram_udqm
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [19:0]  latch_address;
    logic   [7:0]   latch_data;
    logic           write_command;
    logic           read_command;

    logic           access_ready;

    //
    // RAM Address Select (0x00000-0x9FFFF)
    //
    assign  ram_address_select_n =  ~((enable_sdram) && ((~address[19]) || ((address[19]) && ~((address[18]) || (address[17])))));
	 //assign  ram_address_select_n =  ~((enable_sdram) && (address >= 20'h010000 && address < 20'h0A0000));


    //
    // Latch I/O Ports
    //
    // Address
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_address   <= 0;
        else
            latch_address   <= address;
    end

    // Data Bus
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data      <= 0;
        else
            latch_data      <= internal_data_bus;
    end

    // Write Command
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_command   <= 1'b0;
        else
            write_command   <= ~ram_address_select_n & ~memory_write_n;
    end

    // Read Command
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_command    <= 1'b0;
        else
            read_command    <= ~ram_address_select_n & ~memory_read_n;
    end


    //
    // SDRAM Controller
    //
    logic   [24:0]  access_address;
    logic   [9:0]   access_num;
    logic   [15:0]  access_data_in;
    logic   [15:0]  access_data_out;
    logic           write_request;
    logic           read_request;
    logic           write_flag;
    logic           read_flag;
    logic           idle;

    KFSDRAM u_KFSDRAM (
        .sdram_clock        (sdram_clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io)
    );


    //
    // State machine
    //
    always_comb begin
        next_state = state;
        casez (state)
            IDLE: begin
                if (write_command)
                    next_state = RAM_WRITE_1;
                else if (read_command)
                    next_state = RAM_READ_1;
            end
            RAM_WRITE_1: begin
                if (~write_command)
                    next_state = WAIT;
                if (write_flag)
                    next_state = RAM_WRITE_2;
            end
            RAM_WRITE_2: begin
                if (~write_command)
                    next_state = WAIT;
                if (~write_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            RAM_READ_1: begin
                if (~read_command)
                    next_state = WAIT;
                if (read_flag)
                    next_state = RAM_READ_2;
            end
            RAM_READ_2: begin
                if (~read_command)
                    next_state = WAIT;
                if (~read_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            COMPLETE_RAM_RW: begin
                if ((~write_command) && (~read_command))
                    next_state = IDLE;
            end
            WAIT: begin
                if (idle)
                    next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge sdram_clock, posedge reset) begin
        if (reset)
            state = IDLE;
        else
            state = next_state;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                access_address  = 25'h0000000;
                access_num      = 10'h000;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {9'h000, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {9'h000, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {9'h000, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {9'h000, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            COMPLETE_RAM_RW: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            WAIT: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b1;
                sdram_udqm      = 1'b1;
            end
        endcase
    end


    //
    // Databus Out
    //
    logic   [15:0]  data_out_tmp;

    always_ff @(posedge sdram_clock, posedge reset) begin
        if (reset)
            data_out_tmp <= 0;
        else if (read_flag)
            data_out_tmp <= access_data_out;
        else if (read_command)
            data_out_tmp <= data_out_tmp;
        else
            data_out_tmp <= 0;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out <= 0;
        else
            data_bus_out <= data_out_tmp[7:0];
    end


    //
    // Ready/Wait Signal
    //
    always_ff @(posedge sdram_clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else
            access_ready <= 1'b0;
    end

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n))) ? access_ready : 1'b1;

endmodule

