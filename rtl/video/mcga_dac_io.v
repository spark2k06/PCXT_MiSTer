//============================================================================
//
//  MCGA/VGA DAC I/O port frontend
//
//============================================================================

module mcga_dac_io(
    input  wire        clock,
    input  wire        reset,

    input  wire        read_index_write,
    input  wire        write_index_write,
    input  wire        data_write,
    input  wire        read_index_read,
    input  wire        write_index_read,
    input  wire        data_read,
    input  wire [7:0]  io_data_in,
    output reg  [7:0]  io_data_out,

    input  wire [7:0]  sample_index,
    output wire [5:0]  sample_red,
    output wire [5:0]  sample_green,
    output wire [5:0]  sample_blue,
    output wire [7:0]  sample_red_8,
    output wire [7:0]  sample_green_8,
    output wire [7:0]  sample_blue_8
);

    reg [7:0] write_index = 8'h00;
    reg [7:0] read_index = 8'h00;
    reg [1:0] write_component = 2'd0;
    reg [1:0] read_component = 2'd0;

    wire [5:0] port_red;
    wire [5:0] port_green;
    wire [5:0] port_blue;
    wire [5:0] read_component_data = (read_component == 2'd0) ? port_red :
                                      (read_component == 2'd1) ? port_green :
                                      port_blue;

    wire component_write_en = data_write;
    wire [7:0] component_write_index = write_index;
    wire [1:0] component_select = write_component;
    wire [5:0] component_data = io_data_in[5:0];

    mcga_dac dac (
        .clock                  (clock),
        .reset                  (reset),
        .write_en               (1'b0),
        .write_index            (8'h00),
        .write_red              (6'h00),
        .write_green            (6'h00),
        .write_blue             (6'h00),
        .component_write_en     (component_write_en),
        .component_write_index  (component_write_index),
        .component_select       (component_select),
        .component_data         (component_data),
        .sample_index           (sample_index),
        .sample_red             (sample_red),
        .sample_green           (sample_green),
        .sample_blue            (sample_blue),
        .sample_red_8           (sample_red_8),
        .sample_green_8         (sample_green_8),
        .sample_blue_8          (sample_blue_8),
        .port_index             (read_index),
        .port_red               (port_red),
        .port_green             (port_green),
        .port_blue              (port_blue)
    );

    always @(*) begin
        if (read_index_read)
            io_data_out = read_index;
        else if (write_index_read)
            io_data_out = write_index;
        else if (data_read)
            io_data_out = {2'b00, read_component_data};
        else
            io_data_out = 8'h00;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            write_index <= 8'h00;
            read_index <= 8'h00;
            write_component <= 2'd0;
            read_component <= 2'd0;
        end else begin
            if (read_index_write) begin
                read_index <= io_data_in;
                read_component <= 2'd0;
            end

            if (write_index_write) begin
                write_index <= io_data_in;
                write_component <= 2'd0;
            end

            if (data_write) begin
                if (write_component == 2'd2) begin
                    write_component <= 2'd0;
                    write_index <= write_index + 8'd1;
                end else begin
                    write_component <= write_component + 2'd1;
                end
            end

            if (data_read) begin
                if (read_component == 2'd2) begin
                    read_component <= 2'd0;
                    read_index <= read_index + 8'd1;
                end else begin
                    read_component <= read_component + 2'd1;
                end
            end
        end
    end

endmodule
