//
// KFPC-XT Peripherals
// Written by kitune-san
//
module RAM (
    input   logic           clock,
    input   logic           sdram_clock,
    input   logic           reset,
    input   logic           sdram_reset,
    input   logic           enable_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
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
    output  logic           sdram_udqm,
	 // EMS	 
	 input   logic   [6:0]   map_ems[0:3],	 
	 input   logic           ems_b1,
	 input   logic           ems_b2,
	 input   logic           ems_b3,
	 input   logic           ems_b4
	 
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [21:0]  latch_address_ff;
    logic   [21:0]  latch_address;
    logic   [7:0]   latch_data_ff;
    logic   [7:0]   latch_data;
    logic           write_command_ff_1;
    logic           write_command_ff_2;
    logic           write_command;
    logic           read_command_ff_1;
    logic           read_command_ff_2;
    logic           read_command;
    logic           no_command_state_ff_1;
    logic           no_command_state_ff_2;
    logic           no_command_state_ff_3;
    logic           enable_refresh;

    logic           access_ready;

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xEBFFF)
    //	 
	 assign  ram_address_select_n = ~(enable_sdram && 
	                                ~(address[19:16] == 4'b1111) &&  // B0000h reserved for VRAM
											  ~(address[19:16] == 4'b1011) &&  // F0000h reserved for BIOS
											  ~(address[19:14] == 6'b111011)); // EC000h reserved for XTIDE
											  

    //
    // Latch I/O Ports
    //
    // Address
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            latch_address_ff   <= 0;
        else begin
		  			
			  if (ems_b1)
					latch_address_ff   <= {1'b1, map_ems[0], address[13:0]};
			  else if (ems_b2)
					latch_address_ff   <= {1'b1, map_ems[1], address[13:0]};
			  else if (ems_b3)
					latch_address_ff   <= {1'b1, map_ems[2], address[13:0]};
			  else if (ems_b4)
					latch_address_ff   <= {1'b1, map_ems[3], address[13:0]};
			  else
					latch_address_ff   <= {2'b00, address};
				
		  end
		  
    end

    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
            latch_address   <= 0;
        else
            latch_address   <= latch_address_ff;
    end

    // Data Bus
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset) begin
            latch_data_ff   <= 0;
            latch_data      <= 0;
        end
        else begin
            latch_data_ff   <= internal_data_bus;
            latch_data      <= latch_data_ff;
        end
    end

    // Write Command
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset) begin
            write_command_ff_1  <= 1'b0;
            write_command_ff_2  <= 1'b0;
            write_command       <= 1'b0;
        end
        else begin
            write_command_ff_1  <= ~ram_address_select_n & ~memory_write_n;
            write_command_ff_2  <= write_command_ff_1;
            write_command       <= write_command_ff_2;
        end
    end

    // Read Command
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset) begin
            read_command_ff_1   <= 1'b0;
            read_command_ff_2   <= 1'b0;
            read_command        <= 1'b0;
        end
        else begin
            read_command_ff_1   <= ~ram_address_select_n & ~memory_read_n;
            read_command_ff_2   <= read_command_ff_1;
            read_command        <= read_command_ff_2;
        end
    end

    // Generate refresh timing
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset) begin
            no_command_state_ff_1 <= 1'b0;
            no_command_state_ff_2 <= 1'b0;
            no_command_state_ff_3 <= 1'b0;
        end
        else begin
            no_command_state_ff_1 <= no_command_state;
            no_command_state_ff_2 <= no_command_state_ff_1;
            no_command_state_ff_3 <= no_command_state_ff_2;
        end
    end

    assign  enable_refresh  = no_command_state_ff_2 & ~no_command_state_ff_3;


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
        .sdram_clock        (sdram_clock),
        .sdram_reset        (sdram_reset),
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

    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
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
    logic   [15:0]  data_out_tmp;

    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
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
    always_ff @(posedge sdram_clock, posedge sdram_reset) begin
        if (sdram_reset)
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

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n))) ? access_ready : 1'b1;

endmodule

