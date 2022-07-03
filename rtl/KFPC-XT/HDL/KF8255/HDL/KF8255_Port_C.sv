//
// KF8255_port_c
// Port C
//
// Written by Kitune-san
//

`include "KF8255_Definitions.svh"

module KF8255_Port_C (
    // Bus
    input   logic           clock,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           read_enable_n,

    input   logic   [7:0]   internal_data_bus,
    input   logic           write_port_a,
    input   logic           write_port_b,
    input   logic           write_port_c_bit_set,
    input   logic           write_port_c,
    input   logic           read_port_a,
    input   logic           read_port_b,
    input   logic           read_port_c,
    input   logic           update_group_a_mode,
    input   logic           update_group_b_mode,

    // Control Data Registers
    input   logic   [1:0]   group_a_mode_reg,
    input   logic   [1:0]   group_b_mode_reg,
    input   logic           group_a_port_a_io_reg,
    input   logic           group_b_port_b_io_reg,
    input   logic           group_a_port_c_io_reg,
    input   logic           group_b_port_c_io_reg,

    // Signals
    output  logic           port_a_strobe,
    output  logic           port_b_strobe,
    output  logic           port_a_hiz,

    // Ports
    output  logic   [7:0]   port_c_io,
    output  logic   [7:0]   port_c_out,
    input   logic   [7:0]   port_c_in,
    output  logic   [7:0]   port_c_read
);

    //
    // Internal signals
    //
    logic   read_port_a_ff;
    logic   read_port_b_ff;

    logic   stb_a_n;
    logic   ibf_a;
    logic   obf_a_n;
    logic   ack_a_n;
    logic   intr_a;
    logic   intr_a_mode2_read;
    logic   intr_a_mode2_write;
    logic   intr_a_mode2_read_reg;
    logic   intr_a_mode2_write_reg;
    logic   inte_a;
    logic   inte_1;
    logic   inte_2;

    logic   stb_b_n;
    logic   ibf_b;
    logic   obf_b_n;
    logic   ack_b_n;
    logic   intr_b;
    logic   inte_b;

    logic   [2:0]   update_group_a_mode_reg;
    logic   [2:0]   update_group_b_mode_reg;
    logic           update_group_a_port_a_io_reg;
    logic           update_group_b_port_b_io_reg;
    logic   [7:0]   port_c_read_comb;

    //
    // Modes
    //

    // Read edge
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            read_port_a_ff <= 1'b0;
            read_port_b_ff <= 1'b0;
        end
        else begin
            read_port_a_ff <= read_port_a;
            read_port_b_ff <= read_port_b;
        end
    end

    // /STB A
    assign stb_a_n = (port_c_io[4] == `PORT_INPUT) ? port_c_in[4] : 1'b1;
    assign port_a_strobe = ~stb_a_n;

    // IBF A
    always_comb begin
        ibf_a = port_c_out[5];

        if (~stb_a_n)
            ibf_a = 1'b1;

        if (read_port_a != read_port_a_ff)
            if (read_port_a == 1'b0)
                ibf_a = 1'b0;
    end

    // /OBF A
    always_comb begin
        obf_a_n = port_c_out[7];

        if (write_port_a)
            obf_a_n = 1'b0;

        if (~ack_a_n)
            obf_a_n = 1'b1;
    end

    // /ACK A
    assign ack_a_n = (port_c_io[6] == `PORT_INPUT) ? port_c_in[6] : 1'b1;

    // HI-Z
    assign port_a_hiz = ack_a_n;

    // INTR A
    always_comb begin
        intr_a = port_c_out[3];
        intr_a_mode2_read  = intr_a_mode2_read_reg;
        intr_a_mode2_write = intr_a_mode2_write_reg;

        casez (group_a_mode_reg)
            `KF8255_CONTROL_MODE_2: begin
                if (inte_2) begin
                    if (stb_a_n & ibf_a)
                        intr_a_mode2_read = 1'b1;

                    if (read_port_a != read_port_a_ff)
                        if (read_port_a == 1'b1)
                            intr_a_mode2_read = 1'b0;
                end
                else
                    intr_a_mode2_read = 1'b0;

                if (inte_1) begin
                    if (ack_a_n & obf_a_n)
                        intr_a_mode2_write = 1'b1;

                    if (write_port_a)
                        intr_a_mode2_write = 1'b0;
                end
                else
                    intr_a_mode2_write = 1'b0;

                intr_a = intr_a_mode2_read | intr_a_mode2_write;
            end
            default: begin
                if (group_a_port_a_io_reg == `PORT_INPUT) begin
                    if (stb_a_n & ibf_a & inte_a)
                        intr_a = 1'b1;

                    if (read_port_a != read_port_a_ff)
                        if (read_port_a == 1'b1)
                            intr_a = 1'b0;
                end
                else begin
                    if (ack_a_n & obf_a_n & inte_a)
                        intr_a = 1'b1;

                    if (write_port_a)
                        intr_a = 1'b0;
                end

                if (~inte_a)
                    intr_a = 1'b0;
            end
        endcase
    end

    // INTE A
    assign inte_a = (group_a_port_a_io_reg == `PORT_INPUT) ? port_c_out[4] : port_c_out[6];

    // INTE 2
    assign inte_1 = port_c_out[6];
    assign inte_2 = port_c_out[4];


    // /STB B
    assign stb_b_n = (port_c_io[2] == `PORT_INPUT) ? port_c_in[2] : 1'b1;
    assign port_b_strobe = ~stb_b_n;

    // IBF B
    always_comb begin
        ibf_b = port_c_out[1];

        if (~stb_b_n)
            ibf_b = 1'b1;

        if (read_port_b != read_port_b_ff)
            if (read_port_b == 1'b0)
                ibf_b = 1'b0;
    end

    // /OBF B
    always_comb begin
        obf_b_n = port_c_out[1];

        if (write_port_b)
            obf_b_n = 1'b0;

        if (~ack_b_n)
            obf_b_n = 1'b1;
    end

    // /ACK B
    assign ack_b_n = (port_c_io[2] == `PORT_INPUT) ? port_c_in[2] : 1'b1;

    // INTR B
    always_comb begin
        intr_b = port_c_out[0];

        if (group_b_port_b_io_reg == `PORT_INPUT) begin
            if (stb_b_n & ibf_b & inte_b)
                intr_b = 1'b1;

            if (read_port_b != read_port_b_ff)
                if (read_port_b == 1'b1)
                    intr_b = 1'b0;
        end
        else begin
            if (ack_b_n & obf_b_n & inte_b)
                intr_b = 1'b1;

            if (write_port_b)
                intr_b = 1'b0;
        end

        if (~inte_b)
            intr_b = 1'b0;
    end

    // INTE B
    assign inte_b = port_c_out[2];


    //
    // Select port c I/O
    //
    logic   [7:0]   port_c_io_comb;

    always_comb begin
        port_c_io_comb[0] = `PORT_INPUT;
        port_c_io_comb[1] = `PORT_INPUT;
        port_c_io_comb[2] = `PORT_INPUT;
        port_c_io_comb[3] = `PORT_INPUT;
        port_c_io_comb[4] = `PORT_INPUT;
        port_c_io_comb[5] = `PORT_INPUT;
        port_c_io_comb[6] = `PORT_INPUT;
        port_c_io_comb[7] = `PORT_INPUT;

        // Group B
        casez (group_b_mode_reg)
            `KF8255_CONTROL_MODE_0: begin
                if (group_b_port_c_io_reg == `PORT_OUTPUT) begin
                    port_c_io_comb[0] = `PORT_OUTPUT;
                    port_c_io_comb[1] = `PORT_OUTPUT;
                    port_c_io_comb[2] = `PORT_OUTPUT;
                    port_c_io_comb[3] = `PORT_OUTPUT;   // if group a is mode 0
                end
            end
            `KF8255_CONTROL_MODE_1: begin
                if (group_b_port_b_io_reg == `PORT_INPUT) begin
                    port_c_io_comb[0] = `PORT_OUTPUT;
                    port_c_io_comb[1] = `PORT_OUTPUT;
                    port_c_io_comb[2] = `PORT_INPUT;
                end
                else begin
                    port_c_io_comb[0] = `PORT_OUTPUT;
                    port_c_io_comb[1] = `PORT_OUTPUT;
                    port_c_io_comb[2] = `PORT_INPUT;
                end

                if (group_b_port_c_io_reg == `PORT_OUTPUT)
                    port_c_io_comb[3] = `PORT_OUTPUT;   // if group a is mode 0
            end
            default: begin
            end
        endcase

        // Group A
        casez (group_a_mode_reg)
            `KF8255_CONTROL_MODE_0: begin
                if (group_a_port_c_io_reg == `PORT_OUTPUT) begin
                    port_c_io_comb[4] = `PORT_OUTPUT;
                    port_c_io_comb[5] = `PORT_OUTPUT;
                    port_c_io_comb[6] = `PORT_OUTPUT;
                    port_c_io_comb[7] = `PORT_OUTPUT;
                end
            end
            `KF8255_CONTROL_MODE_1: begin
                if (group_a_port_a_io_reg == `PORT_INPUT) begin
                    port_c_io_comb[3] = `PORT_OUTPUT;
                    port_c_io_comb[4] = `PORT_INPUT;
                    port_c_io_comb[5] = `PORT_OUTPUT;

                    if (group_a_port_c_io_reg == `PORT_OUTPUT) begin
                        port_c_io_comb[6] = `PORT_OUTPUT;
                        port_c_io_comb[7] = `PORT_OUTPUT;
                    end
                end
                else begin
                    port_c_io_comb[3] = `PORT_OUTPUT;
                    port_c_io_comb[6] = `PORT_INPUT;
                    port_c_io_comb[7] = `PORT_OUTPUT;

                    if (group_a_port_c_io_reg == `PORT_OUTPUT) begin
                        port_c_io_comb[4] = `PORT_OUTPUT;
                        port_c_io_comb[5] = `PORT_OUTPUT;
                    end
                end
            end
            `KF8255_CONTROL_MODE_2: begin
                    port_c_io_comb[3] = `PORT_OUTPUT;
                    port_c_io_comb[4] = `PORT_INPUT;
                    port_c_io_comb[5] = `PORT_OUTPUT;
                    port_c_io_comb[6] = `PORT_INPUT;
                    port_c_io_comb[7] = `PORT_OUTPUT;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            port_c_io[0] <= `PORT_INPUT;
            port_c_io[1] <= `PORT_INPUT;
            port_c_io[2] <= `PORT_INPUT;
            port_c_io[3] <= `PORT_INPUT;
            port_c_io[4] <= `PORT_INPUT;
            port_c_io[5] <= `PORT_INPUT;
            port_c_io[6] <= `PORT_INPUT;
            port_c_io[7] <= `PORT_INPUT;
        end
        else
            port_c_io <= port_c_io_comb;
    end


    //
    // Output
    //
    assign update_group_a_mode_reg = internal_data_bus[6:5];
    assign update_group_b_mode_reg = {1'b0, internal_data_bus[2]};
    assign update_group_a_port_a_io_reg = internal_data_bus[4];
    assign update_group_b_port_b_io_reg = internal_data_bus[1];

    // PC0 (INTRB | INTRB)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[0] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b000))
            port_c_out[0] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[0] <= internal_data_bus[0];
        else if (update_group_b_mode)
            port_c_out[0] <= 1'b0;
        else
            casez (group_b_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[0] <= port_c_out[0];
                `KF8255_CONTROL_MODE_1: port_c_out[0] <= intr_b;
                default:                port_c_out[0] <= port_c_out[0];
            endcase
    end

    // PC1 (IBFB | /OBFB)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[1] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b001))
            port_c_out[1] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[1] <= internal_data_bus[1];
        else if (update_group_b_mode)
            casez (update_group_b_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[1] <= 1'b0;
                `KF8255_CONTROL_MODE_1: port_c_out[1] <= (update_group_b_port_b_io_reg == `PORT_INPUT) ? 1'b0 : 1'b1;
                default:                port_c_out[1] <= 1'b0;
            endcase
        else
            casez (group_b_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[1] <= port_c_out[1];
                `KF8255_CONTROL_MODE_1: port_c_out[1] <= (group_b_port_b_io_reg == `PORT_INPUT) ? ibf_b : obf_b_n;
                default:                port_c_out[1] <= 1'b0;
            endcase
    end

    // PC2 (/STBB(INTEB) | /ACKB(INTEB))
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[2] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b010))
            port_c_out[2] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[2] <= internal_data_bus[2];
        else if (update_group_b_mode)
            port_c_out[2] <= 1'b0;
        else
            port_c_out[2] <= port_c_out[2];
    end

    // PC3 (INTRA / INTRA)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[3] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b011))
            port_c_out[3] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[3] <= internal_data_bus[3];
        else if (update_group_a_mode)
            port_c_out[3] <= 1'b0;
        else
            casez (group_a_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[3] <= port_c_out[3];
                `KF8255_CONTROL_MODE_1: port_c_out[3] <= intr_a;
                `KF8255_CONTROL_MODE_2: port_c_out[3] <= intr_a;
                default:         port_c_out[3] <= port_c_out[3];
            endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            intr_a_mode2_read_reg  <= 1'b0;
            intr_a_mode2_write_reg <= 1'b0;
        end
        else begin
            intr_a_mode2_read_reg  <= intr_a_mode2_read ;
            intr_a_mode2_write_reg <= intr_a_mode2_write;
        end
    end


    // PC4 (/STBA(INTE2) | I/O)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[4] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b100))
            port_c_out[4] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[4] <= internal_data_bus[4];
        else if (update_group_a_mode)
            port_c_out[4] <= 1'b0;
        else
            port_c_out[4] <= port_c_out[4];
    end

    // PC5 (IBFA | I/O)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[5] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b101))
            port_c_out[5] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[5] <= internal_data_bus[5];
        else if (update_group_a_mode)
            port_c_out[5] <= 1'b0;
        else
            casez (group_a_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[5] <= port_c_out[5];
                `KF8255_CONTROL_MODE_1: port_c_out[5] <= (group_a_port_a_io_reg == `PORT_INPUT) ? ibf_a : port_c_out[5];
                `KF8255_CONTROL_MODE_2: port_c_out[5] <= ibf_a;
                default:         port_c_out[5] <= port_c_out[5];
            endcase
    end

    // PC6 (I/O | /ACKA(INTEA))
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[6] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b110))
            port_c_out[6] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[6] <= internal_data_bus[6];
        else if (update_group_a_mode)
            port_c_out[6] <= 1'b0;
        else
            port_c_out[6] <= port_c_out[6];
    end

    // PC7 (I/O | /OBFA)
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_out[7] <= 1'b0;
        else if ((write_port_c_bit_set) && (internal_data_bus[3:1] == 3'b111))
            port_c_out[7] <= internal_data_bus[0];
        else if (write_port_c)
            port_c_out[7] <= internal_data_bus[7];
        else if (update_group_a_mode)
            casez (update_group_a_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[7] <= 1'b0;
                `KF8255_CONTROL_MODE_1: port_c_out[7] <= (update_group_a_port_a_io_reg == `PORT_INPUT) ? 1'b0 : 1'b1;
                `KF8255_CONTROL_MODE_2: port_c_out[7] <= 1'b1;
                default:         port_c_out[7] <= 1'b0;
            endcase
        else
            casez (group_a_mode_reg)
                `KF8255_CONTROL_MODE_0: port_c_out[7] <= port_c_out[7];
                `KF8255_CONTROL_MODE_1: port_c_out[7] <= (group_a_port_a_io_reg == `PORT_INPUT) ? port_c_out[7] : obf_a_n;
                `KF8255_CONTROL_MODE_2: port_c_out[7] <= obf_a_n;
                default:         port_c_out[7] <= port_c_out[7];
            endcase
    end


    //
    // Input (Read)
    //
    always_comb begin
        port_c_read_comb = port_c_in;

        if (port_c_io[0] == `PORT_OUTPUT)
            port_c_read_comb[0] = port_c_out[0];

        if (port_c_io[1] == `PORT_OUTPUT)
            port_c_read_comb[1] = port_c_out[1];

        if (port_c_io[2] == `PORT_OUTPUT)
            port_c_read_comb[2] = port_c_out[2];

        if (port_c_io[3] == `PORT_OUTPUT)
            port_c_read_comb[3] = port_c_out[3];

        if (port_c_io[4] == `PORT_OUTPUT)
            port_c_read_comb[4] = port_c_out[4];

        if (port_c_io[5] == `PORT_OUTPUT)
            port_c_read_comb[5] = port_c_out[5];

        if (port_c_io[6] == `PORT_OUTPUT)
            port_c_read_comb[6] = port_c_out[6];

        if (port_c_io[7] == `PORT_OUTPUT)
            port_c_read_comb[7] = port_c_out[7];
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            port_c_read <= 8'b00000000;
        else if (update_group_a_mode & update_group_b_mode)
            port_c_read <= 8'b00000000;
        else if (update_group_a_mode)
            port_c_read <= {4'b0000, port_c_read_comb[3:0]};
        else if (update_group_b_mode)
            port_c_read <= {port_c_read_comb[7:4], 4'b0000};
        else
            port_c_read <= port_c_read_comb;
    end

endmodule

