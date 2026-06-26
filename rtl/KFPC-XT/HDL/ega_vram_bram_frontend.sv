module ega_vram_bram_frontend (
    input  logic         clock,
    input  logic         reset,
    input  logic         clk_video,

    input  logic [15:0]  cpu_addr,
    input  logic         cpu_a16,
    input  logic [7:0]   cpu_din,
    input  logic         cpu_read,
    input  logic         cpu_write,
    output logic [7:0]   cpu_dout,
    output logic         cpu_ready,

    input  logic [15:0]  video_addr,
    input  logic         video_read_en,
    output logic [7:0]   video_plane0,
    output logic [7:0]   video_plane1,
    output logic [7:0]   video_plane2,
    output logic [7:0]   video_plane3,
    output logic         video_data_valid,

    input  logic         cfg_toggle,
    input  logic [3:0]   plane_write_mask,
    input  logic         odd_even_mode,
    // Timing hint exported by the sequencer. The BRAM frontend intentionally
    // does not gate CPU transfers with it because CPU and CRT fetches use
    // independent ports and PCXT bus ready timing must remain stable.
    input  logic         cpu_access_en,
    input  logic         chain2_write,
    input  logic         chain2_read,
    input  logic         extended_memory,
    input  logic [1:0]   mem_map_sel,
    input  logic         page_select,
    input  logic [1:0]   write_mode,
    input  logic [1:0]   read_mode,
    input  logic [1:0]   read_plane_sel,
    input  logic [7:0]   color_compare,
    input  logic [7:0]   color_dont_care,
    input  logic [7:0]   bit_mask,
    input  logic [7:0]   set_reset,
    input  logic [3:0]   enable_set_reset,
    input  logic [1:0]   rop_select,
    input  logic [2:0]   rotate_count
);

    typedef enum logic [1:0] {
        CPU_IDLE,
        CPU_WAIT,
        CPU_DONE
    } cpu_state_t;

    cpu_state_t cpu_state;

    logic [15:0] cpu_addr_latched;
    logic        cpu_read_latched;
    logic        cpu_write_latched;

    logic        cfg_toggle_sync1, cfg_toggle_sync2, cfg_toggle_prev;
    logic [3:0]  plane_write_mask_sync1, plane_write_mask_sync2, cfg_plane_write_mask;
    logic        odd_even_mode_sync1, odd_even_mode_sync2, cfg_odd_even_mode;
    logic        chain2_write_sync1, chain2_write_sync2, cfg_chain2_write;
    logic        chain2_read_sync1, chain2_read_sync2, cfg_chain2_read;
    logic        extended_memory_sync1, extended_memory_sync2, cfg_extended_memory;
    logic [1:0]  mem_map_sel_sync1, mem_map_sel_sync2, cfg_mem_map_sel;
    logic        page_select_sync1, page_select_sync2, cfg_page_select;
    logic [1:0]  write_mode_sync1, write_mode_sync2, cfg_write_mode;
    logic [1:0]  read_mode_sync1, read_mode_sync2, cfg_read_mode;
    logic [1:0]  read_plane_sel_sync1, read_plane_sel_sync2, cfg_read_plane_sel;
    logic [7:0]  color_compare_sync1, color_compare_sync2, cfg_color_compare;
    logic [7:0]  color_dont_care_sync1, color_dont_care_sync2, cfg_color_dont_care;
    logic [7:0]  bit_mask_sync1, bit_mask_sync2, cfg_bit_mask;
    logic [7:0]  set_reset_sync1, set_reset_sync2, cfg_set_reset;
    logic [3:0]  enable_set_reset_sync1, enable_set_reset_sync2, cfg_enable_set_reset;
    logic [1:0]  rop_select_sync1, rop_select_sync2, cfg_rop_select;
    logic [2:0]  rotate_count_sync1, rotate_count_sync2, cfg_rotate_count;

    logic [7:0] core_cpu_dout;
    logic [7:0] core_video_plane0;
    logic [7:0] core_video_plane1;
    logic [7:0] core_video_plane2;
    logic [7:0] core_video_plane3;
    logic       video_read_en_q;

    logic core_cpu_select;

    // Keep cpu_select active for IDLE and WAIT so the VRAM core sees
    // cpu_access for 2 cycles: T0=trigger BRAM read, T1=capture BRAM data.
    assign core_cpu_select = ((cpu_state == CPU_IDLE) || (cpu_state == CPU_WAIT))
                           && (cpu_read || cpu_write);
    assign cpu_dout = core_cpu_dout;
    assign cpu_ready = (cpu_state == CPU_DONE);
    assign video_plane0 = core_video_plane0;
    assign video_plane1 = core_video_plane1;
    assign video_plane2 = core_video_plane2;
    assign video_plane3 = core_video_plane3;

    ega_vram u_ega_vram (
        .clk                (clock),
        .clk_vram           (clk_video),
        .cpu_addr           (cpu_addr),
        .cpu_a16            (cpu_a16),
        .cpu_data_in        (cpu_din),
        .cpu_data_out       (core_cpu_dout),
        .cpu_we             (core_cpu_select && cpu_write),
        .cpu_re             (core_cpu_select && cpu_read),
        .cpu_mem_select     (core_cpu_select),
        .plane_write_mask   (cfg_plane_write_mask),
        .odd_even_mode      (cfg_odd_even_mode),
        .chain2_write       (cfg_chain2_write),
        .chain2_read        (cfg_chain2_read),
        .extended_memory    (cfg_extended_memory),
        .mem_map_sel        (cfg_mem_map_sel),
        .page_select        (cfg_page_select),
        .write_mode         (cfg_write_mode),
        .read_mode          (cfg_read_mode),
        .read_plane_sel     (cfg_read_plane_sel),
        .color_compare      (cfg_color_compare),
        .color_dont_care    (cfg_color_dont_care),
        .bit_mask           (cfg_bit_mask),
        .set_reset          (cfg_set_reset),
        .enable_set_reset   (cfg_enable_set_reset),
        .rop_select         (cfg_rop_select),
        .rotate_count       (cfg_rotate_count),
        .crt_addr           (video_addr),
        .crt_re             (video_read_en),
        .crt_plane0         (core_video_plane0),
        .crt_plane1         (core_video_plane1),
        .crt_plane2         (core_video_plane2),
        .crt_plane3         (core_video_plane3)
    );

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            cpu_state <= CPU_IDLE;
            cpu_addr_latched <= 16'h0000;
            cpu_read_latched <= 1'b0;
            cpu_write_latched <= 1'b0;

            cfg_toggle_sync1 <= 1'b0;
            cfg_toggle_sync2 <= 1'b0;
            cfg_toggle_prev <= 1'b0;
            plane_write_mask_sync1 <= 4'h0;
            plane_write_mask_sync2 <= 4'h0;
            cfg_plane_write_mask <= 4'h0;
            odd_even_mode_sync1 <= 1'b0;
            odd_even_mode_sync2 <= 1'b0;
            cfg_odd_even_mode <= 1'b0;
            chain2_write_sync1 <= 1'b0;
            chain2_write_sync2 <= 1'b0;
            cfg_chain2_write <= 1'b0;
            chain2_read_sync1 <= 1'b0;
            chain2_read_sync2 <= 1'b0;
            cfg_chain2_read <= 1'b0;
            extended_memory_sync1 <= 1'b0;
            extended_memory_sync2 <= 1'b0;
            cfg_extended_memory <= 1'b0;
            mem_map_sel_sync1 <= 2'b00;
            mem_map_sel_sync2 <= 2'b00;
            cfg_mem_map_sel <= 2'b00;
            page_select_sync1 <= 1'b0;
            page_select_sync2 <= 1'b0;
            cfg_page_select <= 1'b0;
            write_mode_sync1 <= 2'b00;
            write_mode_sync2 <= 2'b00;
            cfg_write_mode <= 2'b00;
            read_mode_sync1 <= 2'b00;
            read_mode_sync2 <= 2'b00;
            cfg_read_mode <= 2'b00;
            read_plane_sel_sync1 <= 2'b00;
            read_plane_sel_sync2 <= 2'b00;
            cfg_read_plane_sel <= 2'b00;
            color_compare_sync1 <= 8'h00;
            color_compare_sync2 <= 8'h00;
            cfg_color_compare <= 8'h00;
            color_dont_care_sync1 <= 8'h0F;
            color_dont_care_sync2 <= 8'h0F;
            cfg_color_dont_care <= 8'h0F;
            bit_mask_sync1 <= 8'hFF;
            bit_mask_sync2 <= 8'hFF;
            cfg_bit_mask <= 8'hFF;
            set_reset_sync1 <= 8'h00;
            set_reset_sync2 <= 8'h00;
            cfg_set_reset <= 8'h00;
            enable_set_reset_sync1 <= 4'h0;
            enable_set_reset_sync2 <= 4'h0;
            cfg_enable_set_reset <= 4'h0;
            rop_select_sync1 <= 2'b00;
            rop_select_sync2 <= 2'b00;
            cfg_rop_select <= 2'b00;
            rotate_count_sync1 <= 3'b000;
            rotate_count_sync2 <= 3'b000;
            cfg_rotate_count <= 3'b000;
        end else begin
            cfg_toggle_sync1 <= cfg_toggle;
            cfg_toggle_sync2 <= cfg_toggle_sync1;
            plane_write_mask_sync1 <= plane_write_mask;
            plane_write_mask_sync2 <= plane_write_mask_sync1;
            odd_even_mode_sync1 <= odd_even_mode;
            odd_even_mode_sync2 <= odd_even_mode_sync1;
            chain2_write_sync1 <= chain2_write;
            chain2_write_sync2 <= chain2_write_sync1;
            chain2_read_sync1 <= chain2_read;
            chain2_read_sync2 <= chain2_read_sync1;
            extended_memory_sync1 <= extended_memory;
            extended_memory_sync2 <= extended_memory_sync1;
            mem_map_sel_sync1 <= mem_map_sel;
            mem_map_sel_sync2 <= mem_map_sel_sync1;
            page_select_sync1 <= page_select;
            page_select_sync2 <= page_select_sync1;
            write_mode_sync1 <= write_mode;
            write_mode_sync2 <= write_mode_sync1;
            read_mode_sync1 <= read_mode;
            read_mode_sync2 <= read_mode_sync1;
            read_plane_sel_sync1 <= read_plane_sel;
            read_plane_sel_sync2 <= read_plane_sel_sync1;
            color_compare_sync1 <= color_compare;
            color_compare_sync2 <= color_compare_sync1;
            color_dont_care_sync1 <= color_dont_care;
            color_dont_care_sync2 <= color_dont_care_sync1;
            bit_mask_sync1 <= bit_mask;
            bit_mask_sync2 <= bit_mask_sync1;
            set_reset_sync1 <= set_reset;
            set_reset_sync2 <= set_reset_sync1;
            enable_set_reset_sync1 <= enable_set_reset;
            enable_set_reset_sync2 <= enable_set_reset_sync1;
            rop_select_sync1 <= rop_select;
            rop_select_sync2 <= rop_select_sync1;
            rotate_count_sync1 <= rotate_count;
            rotate_count_sync2 <= rotate_count_sync1;

            if (cfg_toggle_sync2 != cfg_toggle_prev) begin
                cfg_toggle_prev <= cfg_toggle_sync2;
                cfg_plane_write_mask <= plane_write_mask_sync2;
                cfg_odd_even_mode <= odd_even_mode_sync2;
                cfg_chain2_write <= chain2_write_sync2;
                cfg_chain2_read <= chain2_read_sync2;
                cfg_extended_memory <= extended_memory_sync2;
                cfg_mem_map_sel <= mem_map_sel_sync2;
                cfg_page_select <= page_select_sync2;
                cfg_write_mode <= write_mode_sync2;
                cfg_read_mode <= read_mode_sync2;
                cfg_read_plane_sel <= read_plane_sel_sync2;
                cfg_color_compare <= color_compare_sync2;
                cfg_color_dont_care <= color_dont_care_sync2;
                cfg_bit_mask <= bit_mask_sync2;
                cfg_set_reset <= set_reset_sync2;
                cfg_enable_set_reset <= enable_set_reset_sync2;
                cfg_rop_select <= rop_select_sync2;
                cfg_rotate_count <= rotate_count_sync2;
            end

            case (cpu_state)
                CPU_IDLE: begin
                    if (cpu_read || cpu_write) begin
                        cpu_addr_latched <= cpu_addr;
                        cpu_read_latched <= cpu_read;
                        cpu_write_latched <= cpu_write;
                        cpu_state <= CPU_WAIT;
                    end
                end

                CPU_WAIT: begin
                    cpu_state <= CPU_DONE;
                end

                CPU_DONE: begin
                    if (~cpu_read && ~cpu_write) begin
                        cpu_read_latched <= 1'b0;
                        cpu_write_latched <= 1'b0;
                        cpu_state <= CPU_IDLE;
                    end
                end

                default: begin
                    cpu_state <= CPU_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge clk_video or posedge reset) begin
        if (reset) begin
            video_read_en_q <= 1'b0;
            video_data_valid <= 1'b0;
        end else begin
            video_read_en_q <= video_read_en;
            video_data_valid <= video_read_en_q;
        end
    end

endmodule
