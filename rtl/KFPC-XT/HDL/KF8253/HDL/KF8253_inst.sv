//
// Install KF8255 (Example)
//

module TOP (
    input   logic           clock,
    input   logic           reset_in,

    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,

    input   logic   [1:0]   address,
    inout   logic   [7:0]   data_bus,

    // I/O
    input   logic           clock_0,
    input   logic           gate_0,
    output  logic           out_0,

    input   logic           clock_1,
    input   logic           gate_1,
    output  logic           out_1,

//    input   logic           clock_2,
    input   logic           gate_2,
    output  logic           out_2
);

    //
    // Internal signals
    //
    logic           res_ff;
    logic           reset;

    logic   [7:0]   data_bus_in;
    logic   [7:0]   data_bus_out;

    logic           counter_0_clock;
    logic           counter_0_gate;
    logic           counter_0_out;

    logic           clock_1_ff;
    logic           gate_1_ff;
    logic           counter_1_clock;
    logic           counter_1_gate;
    logic           counter_1_out;

    logic           counter_2_clock;
    logic           counter_2_gate;
    logic           counter_2_out;


    //
    // RESET
    //
    always_ff @(negedge clock, posedge reset_in) begin
        if (reset_in) begin
            res_ff <= 1'b1;
            reset  <= 1'b1;
        end
        else begin
            res_ff <= 1'b0;
            reset  <= res_ff;
        end
    end


    //
    // Data bus
    //
    assign data_bus = (~chip_select_n & ~read_enable_n & write_enable_n) ? data_bus_out : 8'bzzzzzzzz;
    assign data_bus_in = data_bus;


    //
    // Counter #0 : Synchronous input(clock)
    //
    assign counter_0_clock = clock_0;
    assign counter_0_gate  = gate_0;
    assign out_0 = counter_0_out;


    //
    // Counter #1 : Asynchronous input(clock)
    //
    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            clock_1_ff <= 1'b0;
            counter_1_clock <= 1'b0;
        end
        else begin
            clock_1_ff <= clock_1;
            counter_1_clock <= clock_1_ff;
        end
    end

    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            gate_1_ff <= 1'b0;
            counter_1_gate <= 1'b0;
        end
        else begin
            gate_1_ff <= gate_1;
            counter_1_gate <= gate_1_ff;
        end
    end

    assign out_1 = counter_1_out;


    //
    // Counter #2 : Divided clock
    //
    always_ff @(negedge clock, posedge reset) begin
        if (reset)
            counter_2_clock = 1'b0;
        else
            counter_2_clock = ~counter_2_clock;
    end

    assign counter_2_gate  = gate_2;
    assign out_2 = counter_2_out   ;


    //
    // Install KF8253
    //
    KF8253 u_KF8253 (.*);

endmodule
