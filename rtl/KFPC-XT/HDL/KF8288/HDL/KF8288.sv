//
// KF8288
// 8288-LIKE BUS CONTROLLER
//
// Written by Kitune-san
//

module KF8288 (
    // Control input
    input   logic           clock,
    input   logic           cpu_clock,
    input   logic           reset,
    input   logic           address_enable_n,
    input   logic           command_enable,
    input   logic           io_bus_mode,

    // Processor status
    input   logic   [2:0]   processor_status,

    // Command bus
    // I/O
    output  logic           enable_io_command,
    output  logic           advanced_io_write_command_n,
    output  logic           io_write_command_n,
    output  logic           io_read_command_n,
    output  logic           interrupt_acknowledge_n,
    // Memory
    output  logic           enable_memory_command,
    output  logic           advanced_memory_write_command_n,
    output  logic           memory_write_command_n,
    output  logic           memory_read_command_n,

    // Control output
    output  logic           direction_transmit_or_receive_n,
    output  logic           data_enable,
    output  logic           master_cascade_enable,
    output  logic           peripheral_data_enable_n,
    output  logic           address_latch_enable
);

    //
    // CPU clock edge
    //
    logic   prev_cpu_clock;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_cpu_clock <= 1'b0;
        else
            prev_cpu_clock <= cpu_clock;
    end

    wire    cpu_clock_posedge = ~prev_cpu_clock & cpu_clock;
    wire    cpu_clock_negedge = prev_cpu_clock & ~cpu_clock;


    //
    // Status decoder
    //
    wire    is_interrupt_acknowledge_status = (processor_status == 3'b000);
    wire    is_read_io_port_status          = (processor_status == 3'b001);
    wire    is_write_io_port_status         = (processor_status == 3'b010);
    wire    is_halt_status                  = (processor_status == 3'b011);
    wire    is_code_access_status           = (processor_status == 3'b100);
    wire    is_read_memory_status           = (processor_status == 3'b101);
    wire    is_write_memory_status          = (processor_status == 3'b110);
    wire    is_passive_status               = (processor_status == 3'b111);

    logic   strobed_interrupt_acknowledge_status;
    logic   strobed_read_io_port_status;
    logic   strobed_write_io_port_status;
    logic   strobed_halt_status;
    logic   strobed_code_access_status;
    logic   strobed_read_memory_status;
    logic   strobed_write_memory_status;

    // Strobe processor status
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            strobed_interrupt_acknowledge_status <= 1'b0;
            strobed_read_io_port_status          <= 1'b0;
            strobed_write_io_port_status         <= 1'b0;
            strobed_halt_status                  <= 1'b0;
            strobed_code_access_status           <= 1'b0;
            strobed_read_memory_status           <= 1'b0;
            strobed_write_memory_status          <= 1'b0;
        end
        else if (cpu_clock_negedge) begin
            strobed_interrupt_acknowledge_status <= is_interrupt_acknowledge_status;
            strobed_read_io_port_status          <= is_read_io_port_status;
            strobed_write_io_port_status         <= is_write_io_port_status;
            strobed_halt_status                  <= is_halt_status;
            strobed_code_access_status           <= is_code_access_status;
            strobed_read_memory_status           <= is_read_memory_status;
            strobed_write_memory_status          <= is_write_memory_status;
        end
        else begin
            strobed_interrupt_acknowledge_status <= strobed_interrupt_acknowledge_status;
            strobed_read_io_port_status          <= strobed_read_io_port_status;
            strobed_write_io_port_status         <= strobed_write_io_port_status;
            strobed_halt_status                  <= strobed_halt_status;
            strobed_code_access_status           <= strobed_code_access_status;
            strobed_read_memory_status           <= strobed_read_memory_status;
            strobed_write_memory_status          <= strobed_write_memory_status;
        end
    end


    //
    // Control Logic
    //
    logic           machine_cycle_period;
    logic   [2:0]   machine_cycle;

    // Generate machine cycle period
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            machine_cycle_period <= 1'b1;
        else if (cpu_clock_posedge)
            if (machine_cycle == 3'b000)
                if (is_passive_status)
                    machine_cycle_period <= 1'b1;
                else
                    machine_cycle_period <= 1'b0;
            else
                machine_cycle_period <= 1'b0;
        else
            machine_cycle_period <= machine_cycle_period;
    end

    // Generate machine cycle
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            machine_cycle <= 3'b000;
        else if (cpu_clock_negedge)
            if (is_passive_status)
                machine_cycle <= 3'b000;
            else if (machine_cycle_period)
                machine_cycle <= 3'b000;
            else
                machine_cycle <= {machine_cycle[1:0], 1'b1};
        else
            machine_cycle <= machine_cycle;
    end


    //
    // Command signal generator
    //
    wire    read_and_advanced_write_command_n = ~(machine_cycle[0] == 1'b1);
    wire    write_command_n                   = ~(machine_cycle[1] == 1'b1);

    // Command
    always_comb begin
        advanced_io_write_command_n     = 1'b1;
        io_write_command_n              = 1'b1;
        io_read_command_n               = 1'b1;
        advanced_memory_write_command_n = 1'b1;
        memory_write_command_n          = 1'b1;
        memory_read_command_n           = 1'b1;
        interrupt_acknowledge_n         = 1'b1;

        if (command_enable) begin
            if (strobed_interrupt_acknowledge_status) begin
                interrupt_acknowledge_n         = read_and_advanced_write_command_n;
            end

            if (strobed_read_io_port_status) begin
                io_read_command_n               = read_and_advanced_write_command_n;
            end

            if (strobed_write_io_port_status) begin
                io_write_command_n              = write_command_n;
                advanced_io_write_command_n     = read_and_advanced_write_command_n;
            end

            if (strobed_code_access_status) begin
                memory_read_command_n           = read_and_advanced_write_command_n;
            end

            if (strobed_read_memory_status) begin
                memory_read_command_n           = read_and_advanced_write_command_n;
            end

            if (strobed_write_memory_status) begin
                advanced_memory_write_command_n = read_and_advanced_write_command_n;
                memory_write_command_n          = write_command_n;
            end
        end
    end

    // Command enable
    always_comb begin
        if (address_enable_n) begin
            enable_io_command     = 1'b0;
            enable_memory_command = 1'b0;
        end
        else begin
            enable_io_command     = 1'b1;
            enable_memory_command = 1'b1;
        end

        if (io_bus_mode)
            enable_io_command     = 1'b1;
    end


    //
    // Control signal generator
    //
    logic       write_command_tmp;
    logic       write_data_enable;
    logic       read_command_tmp;
    logic       read_data_enable;

    // Generate bus direction signal
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            direction_transmit_or_receive_n <= 1'b1;
        else if (cpu_clock_posedge)
            if (machine_cycle_period) begin
                if (is_interrupt_acknowledge_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (is_read_io_port_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (is_write_io_port_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else if (is_halt_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else if (is_code_access_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (is_read_memory_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (is_write_memory_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else
                    direction_transmit_or_receive_n <= 1'b1;
            end
            else begin
                if (strobed_interrupt_acknowledge_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (strobed_read_io_port_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (strobed_write_io_port_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else if (strobed_halt_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else if (strobed_code_access_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (strobed_read_memory_status)
                    direction_transmit_or_receive_n <= 1'b0;
                else if (strobed_write_memory_status)
                    direction_transmit_or_receive_n <= 1'b1;
                else
                    direction_transmit_or_receive_n <= 1'b1;
            end
        else
            direction_transmit_or_receive_n <= direction_transmit_or_receive_n;
    end

    // Generate data enable signal
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_command_tmp <= 1'b0;
        else if (cpu_clock_negedge)
            if (machine_cycle_period)
                write_command_tmp <= 1'b0;
            else if (is_halt_status)
                write_command_tmp <= 1'b0;
            else if (strobed_halt_status)
                write_command_tmp <= 1'b0;
            else
                write_command_tmp <= 1'b1;
        else
            write_command_tmp <= write_command_tmp;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_command_tmp <= 1'b0;
        else if (cpu_clock_posedge)
            read_command_tmp <= ~read_and_advanced_write_command_n;
        else
            read_command_tmp <= read_command_tmp;
    end

    assign write_data_enable = write_command_tmp & ~machine_cycle_period;
    assign read_data_enable  = read_command_tmp  & ~read_and_advanced_write_command_n;
    assign data_enable = command_enable & (direction_transmit_or_receive_n ? write_data_enable : read_data_enable);

    // Generate master cascade enable signal
    assign master_cascade_enable = (machine_cycle == 3'b000) & ~is_passive_status;

    // Generate peripheral data enable signal
    assign peripheral_data_enable_n = ~data_enable;

    // Generate Address latch enable signal
    assign address_latch_enable  = machine_cycle_period      & ~is_passive_status;

endmodule

