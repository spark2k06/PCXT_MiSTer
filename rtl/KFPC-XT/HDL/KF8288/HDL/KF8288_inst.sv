//
// Install KF8288 (Example)
//

module TOP (
    // Control input
    input   logic           clock,
    input   logic           reset_in,
    input   logic           AEN_n,
    input   logic           IOB,
    input   logic           CEN,

    // Processor status
    input   logic   [2:0]   S_n,

    // Command bus
    output  logic           AIOWC_n,
    output  logic           AMWC_n,
    output  logic           IOWC_n,
    output  logic           MWTC_n,
    output  logic           MRDC_n,
    output  logic           IORC_n,
    output  logic           INTA_n,

    output  logic           DT_R_n,
    output  logic           ALE,
    output  logic           MCE_PDEN_n,
    output  logic           DEN
);

    //
    // Internal signals
    //
    logic           res_ff;
    logic           reset;
    logic           enable_io_command;
    logic           advanced_io_write_command_n;
    logic           io_write_command_n;
    logic           io_read_command_n;
    logic           interrupt_acknowledge_n;
    logic           enable_memory_command;
    logic           advanced_memory_write_command_n;
    logic           memory_write_command_n;
    logic           memory_read_command_n;
    logic           peripheral_data_enable_n;
    logic           master_cascade_enable;


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
    // Install KF8253
    //
    KF8288 u_KF8288 (
        .clock                              (clock),
        .reset                              (reset),
        .address_enable_n                   (AEN_n),
        .command_enable                     (CEN),
        .io_bus_mode                        (IOB),
        .processor_status                   (S_n),
        .enable_io_command                  (enable_io_command),
        .advanced_io_write_command_n        (advanced_io_write_command_n),
        .io_write_command_n                 (io_write_command_n),
        .io_read_command_n                  (io_read_command_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .enable_memory_command              (enable_memory_command),
        .advanced_memory_write_command_n    (advanced_memory_write_command_n),
        .memory_write_command_n             (memory_write_command_n),
        .memory_read_command_n              (memory_read_command_n),
        .direction_transmit_or_receive_n    (DT_R_n),
        .data_enable                        (DEN),
        .master_cascade_enable              (master_cascade_enable),
        .peripheral_data_enable_n           (peripheral_data_enable_n),
        .address_latch_enable               (ALE)
    );

    assign AIOWC_n = (enable_io_command)     ?  advanced_io_write_command_n     : 1'bz;
    assign AMWC_n  = (enable_memory_command) ?  advanced_memory_write_command_n : 1'bz;
    assign IOWC_n  = (enable_io_command)     ?  io_write_command_n              : 1'bz;
    assign MWTC_n  = (enable_memory_command) ?  memory_write_command_n          : 1'bz;
    assign MRDC_n  = (enable_memory_command) ?  memory_read_command_n           : 1'bz;
    assign IORC_n  = (enable_io_command)     ?  io_read_command_n               : 1'bz;
    assign INTA_n  = (enable_io_command)     ?  interrupt_acknowledge_n         : 1'bz;
    assign MCE_PDEN_n = (IOB) ? peripheral_data_enable_n : master_cascade_enable;

endmodule
