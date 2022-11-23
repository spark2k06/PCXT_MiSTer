//
// MiSTer PCXT RAM
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
    output  logic           memory_access_ready,
    output  logic           ram_address_select_n,
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
    output  logic           sdram_udqm,
     // EMS
     input   logic   [6:0]   map_ems[0:3],
     input   logic           ems_b1,
     input   logic           ems_b2,
     input   logic           ems_b3,
     input   logic           ems_b4,
     // BIOS
     input  logic    [1:0]  bios_protect_flag,
     input  logic           tandy_bios_flag,
    // Optional flags
    input  logic           enable_a000h,
    // Wait mode
    input   logic           wait_count_clk_en,
    input   logic   [1:0]   ram_read_wait_cycle,
    input   logic   [1:0]   ram_write_wait_cycle
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [21:0]  latch_address;
    logic   [7:0]   latch_data;
    logic           write_command;
    logic           read_command;
    logic           prev_no_command_state;
    logic           enable_refresh;
    logic           write_protect;

    logic   [1:0]   read_wait_count;
    logic   [1:0]   write_wait_count;
    logic           access_ready;

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xFFFFF)
    //
    assign ram_address_select_n = ~(enable_sdram && ~(address[19:16] == 4'b1011) &&  // B0000h reserved for VRAM
	                               ~(~enable_a000h && address[19:16] == 4'b1010));    // A0000h is optional
	 

    assign tandy_bios_select    = tandy_bios_flag & (address[19:16] == 4'b1111);


    //
    // Write protect
    //
    assign write_protect = bios_protect_flag[1] & (address[19:16] == 4'b1111)
                         | bios_protect_flag[0] & (address[19:14] == 6'b111011);


    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (ems_b1)
            latch_address   = {1'b1, map_ems[0], address[13:0]};
        else if (ems_b2)
            latch_address   = {1'b1, map_ems[1], address[13:0]};
        else if (ems_b3)
            latch_address   = {1'b1, map_ems[2], address[13:0]};
        else if (ems_b4)
            latch_address   = {1'b1, map_ems[3], address[13:0]};
        else
            latch_address   = {1'b0, tandy_bios_select, address};
    end

    // Data
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data      <= 0;
        else
            latch_data      <= internal_data_bus;
    end

    // Write Command
    assign write_command = ~ram_address_select_n & ~memory_write_n & ~write_protect;

    // Read Command
    assign read_command  = ~ram_address_select_n & ~memory_read_n;

    // Generate refresh timing
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_no_command_state   <= 1'b0;
        end
        else begin
            prev_no_command_state   <= no_command_state;
        end
    end

    assign  enable_refresh  = no_command_state & ~prev_no_command_state;


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
    logic           refresh_mode;

    KFSDRAM u_KFSDRAM (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
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

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state = IDLE;
        else
            state = next_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            initilized_sdram <= 1'b0;
        else if (idle)
            initilized_sdram <= 1'b1;
        else
            initilized_sdram <= initilized_sdram;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = write_command ? 1'b1 : 1'b0;
                read_request    = read_command  ? 1'b1 : 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {7'h00, latch_address};
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
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out <= 0;
        else if (read_flag)
            data_bus_out <= access_data_out[7:0];
        else if (read_command)
            data_bus_out <= data_bus_out;
        else
            data_bus_out <= 0;
    end


    //
    // Ready/Wait Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else if (state == IDLE)
            access_ready <= idle;
        else if ((write_command) && (refresh_mode))
            access_ready <= 1'b0;
        else if ((read_command)  && (refresh_mode))
            access_ready <= 1'b0;
        else
            access_ready <= access_ready;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_wait_count     <= 0;
        else if (~read_command)
            read_wait_count     <= ram_read_wait_cycle;
        else if ((wait_count_clk_en) && (read_wait_count != 0))
            read_wait_count     <= read_wait_count - 1;
        else
            read_wait_count     <= read_wait_count;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_wait_count    <= 0;
        else if (~write_command)
            write_wait_count    <= ram_write_wait_cycle;
        else if ((wait_count_clk_en) && (write_wait_count != 0))
            write_wait_count    <= write_wait_count - 1;
        else
            write_wait_count    <= write_wait_count;
    end

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n)))
                                        ? (access_ready & ((read_wait_count==0) || (~read_command)) & ((write_wait_count==0) || (~write_command))) : 1'b1;

endmodule

