`timescale 1ns/1ps

// Minimal RAM stubs: the overlay stays disabled, so this bench exercises only
// the production credits block's normal RGB pass-through latency.
module jtframe_dual_ram #(
    parameter dw = 8, aw = 8, synfile = "", ascii_bin = 0
) (
    input wire clk0, clk1,
    input wire [dw-1:0] data0, data1,
    input wire [aw-1:0] addr0, addr1,
    input wire we0, we1,
    output wire [dw-1:0] q0,
    output wire [dw-2:0] q1
);
    assign q0 = {dw{1'b0}};
    assign q1 = {(dw-1){1'b0}};
endmodule

module jtframe_ram #(
    parameter dw = 8, aw = 8, synfile = ""
) (
    input wire clk, cen,
    input wire [dw-1:0] data,
    input wire [aw-1:0] addr,
    input wire we,
    output wire [dw-1:0] q
);
    assign q = {dw{1'b0}};
endmodule

module jtframe_credits_alignment_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg ce_src = 1'b0;
    reg [23:0] rgb_src = 24'd0;
    reg de_src = 1'b0;

    // Model the final video retimer. Its CE and data change on this
    // same edge, while jtframe_credits observes their preceding values.
    reg ce_hdmi = 1'b0;
    reg [23:0] rgb_hdmi = 24'd0;
    reg de_hdmi = 1'b0;
    always @(posedge clk) begin
        ce_hdmi <= ce_src;
        if (ce_src) begin
            rgb_hdmi <= rgb_src;
            de_hdmi <= de_src;
        end
    end

    wire [23:0] rgb_out;
    wire hb_unused;
    wire vb_unused;

    jtframe_credits #(.PAGES(4), .COLW(8), .BLKPOL(1)) dut (
        .rst(rst), .clk(clk), .pxl_cen(ce_hdmi),
        .HB(~de_hdmi), .VB(1'b0), .rgb_in(rgb_hdmi),
        .vram_din(9'd0), .vram_addr(10'd0), .vram_we(1'b0),
        .vram_dout(), .enable(1'b0), .toggle(1'b0),
        .vram_ctrl(3'd0), .fast_scroll(1'b0), .rotate(2'd0),
        .border(1'b0), .HB_out(hb_unused), .VB_out(vb_unused),
        .rgb_out(rgb_out)
    );

    // This is the matching register added at the top level.  It sees the same
    // old input values as jtframe_credits on each nonblocking-assignment edge.
    reg de_out = 1'b0;
    always @(posedge clk) begin
        if (rst)
            de_out <= 1'b0;
        else if (ce_hdmi)
            de_out <= de_hdmi;
    end

    task automatic pixel(input [7:0] value, input active);
        begin
            @(negedge clk);
            rgb_src = {value, 16'd0};
            de_src = active;
            ce_src = 1'b1;
            @(negedge clk);
            ce_src = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    integer count = 0;
    integer errors = 0;
    integer i;

    always @(posedge clk) begin
        #1;
        if (ce_hdmi && de_out) begin
            count = count + 1;
            if (rgb_out[23:16] !== count[7:0]) begin
                errors = errors + 1;
                $display("FAIL visible sample %0d carries %0d", count,
                         rgb_out[23:16]);
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        for (i = 0; i < 8; i = i + 1)
            pixel(8'd0, 1'b0);
        for (i = 1; i <= 8; i = i + 1)
            pixel(i[7:0], 1'b1);
        for (i = 0; i < 8; i = i + 1)
            pixel(8'd0, 1'b0);

        if (count == 8 && errors == 0)
            $display("PASS: credits RGB and registered DE contain pixels 1..8");
        else
            $display("FAIL: count=%0d errors=%0d", count, errors);
        $finish;
    end
endmodule
