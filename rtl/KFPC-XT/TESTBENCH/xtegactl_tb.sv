//============================================================================
//
//  XTEGACTL port block regression.
//
//  Two properties matter.  The block must sit clear of the on-board chip
//  select decoder, which ignores address[15:10] and would otherwise let a
//  write here reach the DMA page registers. Every field except VGA 13h+ must
//  treat zero as "leave it to the OSD"; VGA 13h+ deliberately starts absent
//  and is enabled by VGATSR through its raw XTEGACTL field.
//
//    iverilog -g2012 -o xtegactl_tb TESTBENCH/xtegactl_tb.sv HDL/xtegactl.sv
//    vvp xtegactl_tb
//
//============================================================================

`timescale 1ns/1ps

module xtegactl_tb;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic clear_vga13 = 1'b0;
    always #5 clock = ~clock;

    logic [15:0] address          = 16'h0000;
    logic        address_enable_n = 1'b0;
    logic        io_read_n        = 1'b1;
    logic        io_write_n       = 1'b1;
    logic  [7:0] data_in          = 8'h00;
    wire   [7:0] data_out;
    wire         output_enable;

    // A deliberately non-default OSD, so "deferred to the OSD" cannot pass by
    // accidentally matching a zero.
    logic [1:0] osd_speed        = 2'd2;    // 9.54 MHz
    logic       osd_fake286      = 1'b1;
    logic [1:0] osd_opl2         = 2'd1;    // SB FM
    logic       osd_cms          = 1'b1;
    logic       osd_sb           = 1'b0;
    logic [2:0] osd_sb_irq       = 3'd5;
    logic [3:0] osd_crt_h        = 4'd5;
    logic [2:0] osd_crt_v        = 3'd3;
    logic       osd_ems          = 1'b1;
    logic       osd_umb          = 1'b1;
    logic       osd_joy1_digital = 1'b1;
    logic       osd_joy1_disable = 1'b0;
    logic       osd_joy2_digital = 1'b0;
    logic       osd_joy2_disable = 1'b1;
    logic       osd_joy_sync     = 1'b1;
    logic       osd_joy_swap     = 1'b1;
    logic       osd_mt32_gm      = 1'b1;
    logic       osd_mpu401       = 1'b1;
    logic       osd_tandy        = 1'b0;    // current OSD default: Disabled
    logic [2:0] osd_vsync_w      = 3'd2;
    logic [2:0] osd_hsync_w      = 3'd4;
    logic       build_sb         = 1'b1;
    logic       build_tandy      = 1'b1;

    wire [1:0] eff_speed;
    wire       eff_fake286;
    wire [1:0] eff_opl2;
    wire       eff_cms, eff_ems, eff_umb, eff_vga13;
    wire       eff_sb;
    wire [2:0] eff_sb_irq;
    wire [3:0] eff_crt_h;
    wire [2:0] eff_crt_v;
    wire [2:0] eff_vsync_w, eff_hsync_w;
    wire       eff_joy1_digital, eff_joy1_disable;
    wire       eff_joy2_digital, eff_joy2_disable;
    wire       eff_joy_sync, eff_joy_swap, eff_mt32_gm, eff_mpu401, eff_tandy;
    wire [39:0] status_effective;
    wire [17:0] status_osd_match;

    wire [7:0] reg_cpu, reg_exp, reg_vid, reg_inp, reg_midi, reg_exp2;
    wire [7:0] reg_crt, reg_sync;

    xtegactl dut (
        .clock(clock), .reset(reset), .clear_vga13(clear_vga13),
        .address(address), .address_enable_n(address_enable_n),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out), .output_enable(output_enable),
        .reg_cpu(reg_cpu), .reg_exp(reg_exp), .reg_vid(reg_vid),
        .reg_inp(reg_inp), .reg_midi(reg_midi), .reg_exp2(reg_exp2),
        .reg_crt(reg_crt), .reg_sync(reg_sync),
        .status_effective(status_effective), .status_osd_match(status_osd_match)
    );

    xtegactl_resolve res (
        .reg_cpu(reg_cpu), .reg_exp(reg_exp), .reg_vid(reg_vid),
        .reg_inp(reg_inp), .reg_midi(reg_midi), .reg_exp2(reg_exp2),
        .osd_speed(osd_speed), .osd_fake286(osd_fake286), .osd_opl2(osd_opl2),
        .osd_cms(osd_cms), .osd_sb(osd_sb), .osd_sb_irq(osd_sb_irq), .build_sb(build_sb),
        .reg_crt(reg_crt), .reg_sync(reg_sync),
        .osd_crt_h(osd_crt_h), .osd_crt_v(osd_crt_v),
        .osd_vsync_w(osd_vsync_w), .osd_hsync_w(osd_hsync_w),
        .osd_ems(osd_ems), .osd_umb(osd_umb),
        .osd_joy1_digital(osd_joy1_digital), .osd_joy1_disable(osd_joy1_disable),
        .osd_joy2_digital(osd_joy2_digital), .osd_joy2_disable(osd_joy2_disable),
        .osd_joy_sync(osd_joy_sync), .osd_joy_swap(osd_joy_swap),
        .osd_mt32_gm(osd_mt32_gm), .osd_mpu401(osd_mpu401),
        .osd_tandy(osd_tandy), .build_tandy(build_tandy),
        .eff_speed(eff_speed), .eff_fake286(eff_fake286), .eff_opl2(eff_opl2),
        .eff_cms(eff_cms), .eff_sb(eff_sb), .eff_sb_irq(eff_sb_irq), .eff_ems(eff_ems), .eff_umb(eff_umb),
        .eff_vga13(eff_vga13),
        .eff_joy1_digital(eff_joy1_digital), .eff_joy1_disable(eff_joy1_disable),
        .eff_joy2_digital(eff_joy2_digital), .eff_joy2_disable(eff_joy2_disable),
        .eff_joy_sync(eff_joy_sync), .eff_joy_swap(eff_joy_swap),
        .eff_mt32_gm(eff_mt32_gm), .eff_mpu401(eff_mpu401),
        .eff_tandy(eff_tandy),
        .eff_crt_h(eff_crt_h), .eff_crt_v(eff_crt_v),
        .eff_vsync_w(eff_vsync_w), .eff_hsync_w(eff_hsync_w),
        .status_effective(status_effective), .status_osd_match(status_osd_match)
    );

    integer errors = 0;

    task automatic fail(input string tag);
        begin
            errors = errors + 1;
            $display("FAIL: %s", tag);
        end
    endtask

    task automatic chk(input string tag, input logic got, input logic exp);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL: %s got=%0b expected=%0b", tag, got, exp);
            end
        end
    endtask

    task automatic chk2(input string tag, input logic [1:0] got, input logic [1:0] exp);
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL: %s got=%0d expected=%0d", tag, got, exp);
            end
        end
    endtask

    task automatic io_write(input [15:0] port, input [7:0] value);
        begin
            @(negedge clock);
            address = port; data_in = value; io_write_n = 1'b0;
            @(posedge clock);
            @(negedge clock);
            io_write_n = 1'b1;
        end
    endtask

    task automatic io_read(input [15:0] port, output [7:0] value);
        begin
            @(negedge clock);
            address = port; io_read_n = 1'b0;
            #1 value = data_out;
            if (!output_enable) fail("read did not drive the bus");
            @(negedge clock);
            io_read_n = 1'b1;
        end
    endtask

    logic [7:0] rd;

    task chk3(input string what, input logic [2:0] got, input logic [2:0] want);
        if (got !== want) fail($sformatf("%s got=%0d expected=%0d", what, got, want));
    endtask

    task chk4(input string what, input logic [3:0] got, input logic [3:0] want);
        if (got !== want) fail($sformatf("%s got=%0d expected=%0d", what, got, want));
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        repeat (2) @(posedge clock);

        // ---- every normal field defers to the OSD out of reset ------------
        chk2("speed defers",      eff_speed,        2'd2);
        chk ("fake286 defers",    eff_fake286,      1'b1);
        chk2("opl2 defers",       eff_opl2,         2'd1);
        chk ("cms defers",        eff_cms,          1'b1);
        chk ("ems defers",        eff_ems,          1'b1);
        chk ("umb defers",        eff_umb,          1'b1);
        chk ("vga13 starts disabled", eff_vga13,     1'b0);
        chk ("joy1 type defers",  eff_joy1_digital, 1'b1);
        chk ("joy2 dis defers",   eff_joy2_disable, 1'b1);
        chk ("joy sync defers",   eff_joy_sync,     1'b1);
        chk ("joy swap defers",   eff_joy_swap,     1'b1);
        chk ("mt32 defers",       eff_mt32_gm,      1'b1);
        chk ("mpu401 defers",      eff_mpu401,       1'b1);
        chk ("tandy defers to the OSD", eff_tandy,  1'b0);
        chk3("sb irq defers to the OSD", eff_sb_irq, 3'd5);

        // ---- effective status extension -----------------------------------
        // All fields initially follow the deliberately non-default OSD above,
        // so every field with a match flag should be marked as OSD-controlled.
        io_read(16'h8989, rd);
        if (rd !== 8'h1A) fail($sformatf("effective CPU/audio read %02h expected 1A", rd));
        io_read(16'h898A, rd);
        if (rd !== 8'hCB) fail($sformatf("effective input read %02h expected CB", rd));
        io_read(16'h898B, rd);
        if (rd !== 8'h87) fail($sformatf("effective MIDI/audio read %02h expected 87", rd));
        io_read(16'h898C, rd);
        if (rd !== 8'h35) fail($sformatf("effective CRT read %02h expected 35", rd));
        io_read(16'h898D, rd);
        if (rd !== 8'hE2) fail($sformatf("effective sync/match read %02h expected E2", rd));
        io_read(16'h898E, rd);
        if (rd !== 8'hFF) fail($sformatf("OSD match low read %02h expected FF", rd));
        io_read(16'h898F, rd);
        if (rd !== 8'hFF) fail($sformatf("OSD match high read %02h expected FF", rd));
        // The extension is read-only and must not alter the effective state.
        io_write(16'h8989, 8'hFF);
        io_read(16'h8989, rd);
        if (rd !== 8'h1A) fail("effective status accepted a write");

        // ---- signature ----------------------------------------------------
        io_read(16'h8980, rd);
        if (rd !== 8'h45) fail($sformatf("signature read %02h expected 45", rd));

        // The signature is read only.
        io_write(16'h8980, 8'hFF);
        io_read(16'h8980, rd);
        if (rd !== 8'h45) fail("signature accepted a write");

        // ---- speed ---------------------------------------------------------
        io_write(16'h8981, 8'h01); chk2("speed 1 selects 4.77", eff_speed, 2'd0);
        io_read (16'h8989, rd);
        if (rd !== 8'h18) fail($sformatf("effective speed override read %02h expected 18", rd));
        io_read (16'h898E, rd);
        if (rd !== 8'hFE) fail($sformatf("speed mismatch flag read %02h expected FE", rd));
        io_write(16'h8981, 8'h02); chk2("speed 2 selects 7.16", eff_speed, 2'd1);
        io_write(16'h8981, 8'h03); chk2("speed 3 selects 9.54", eff_speed, 2'd2);
        // A raw override that selects the same value as the OSD is still
        // reported as matching the OSD.
        io_read (16'h898E, rd);
        if (rd !== 8'hFF) fail($sformatf("equal effective value was not marked OSD: %02h", rd));
        io_write(16'h8981, 8'h04); chk2("speed 4 selects Max",  eff_speed, 2'd3);
        // Out of range is not a speed, so it must fall back rather than alias.
        io_write(16'h8981, 8'h05); chk2("speed 5 falls back to the OSD", eff_speed, 2'd2);
        io_write(16'h8981, 8'h07); chk2("speed 7 falls back to the OSD", eff_speed, 2'd2);
        io_write(16'h8981, 8'h00); chk2("speed 0 defers again", eff_speed, 2'd2);

        // ---- fake 286, in the same register --------------------------------
        io_write(16'h8981, 8'h08); chk("fake286 1 forces off", eff_fake286, 1'b0);
        io_write(16'h8981, 8'h10); chk("fake286 2 forces on",  eff_fake286, 1'b1);
        osd_fake286 = 1'b0;
        io_write(16'h8981, 8'h10); chk("fake286 2 forces on over a clear OSD", eff_fake286, 1'b1);
        io_write(16'h8981, 8'h00); chk("fake286 defers again", eff_fake286, 1'b0);
        osd_fake286 = 1'b1;

        // Speed and fake 286 share a register and must not disturb each other.
        io_write(16'h8981, 8'h0A);      // speed=2, fake286=1 (off)
        chk2("speed survives a neighbouring field", eff_speed, 2'd1);
        chk ("fake286 survives a neighbouring field", eff_fake286, 1'b0);
        io_write(16'h8981, 8'h00);

        // ---- expansion ------------------------------------------------------
        io_write(16'h8982, 8'h01); chk2("opl2 1 selects Adlib", eff_opl2, 2'd0);
        io_write(16'h8982, 8'h02); chk2("opl2 2 selects SB FM", eff_opl2, 2'd1);
        io_write(16'h8982, 8'h03); chk2("opl2 3 disables",      eff_opl2, 2'd2);

        io_write(16'h8982, 8'h04); chk("cms 1 enables",  eff_cms, 1'b1);
        io_write(16'h8982, 8'h08); chk("cms 2 disables", eff_cms, 1'b0);
        io_write(16'h8982, 8'h10); chk("ems 1 enables",  eff_ems, 1'b1);
        io_write(16'h8982, 8'h20); chk("ems 2 disables", eff_ems, 1'b0);
        io_write(16'h8982, 8'h40); chk("umb 1 enables",  eff_umb, 1'b1);
        io_write(16'h8982, 8'h80); chk("umb 2 disables", eff_umb, 1'b0);

        // All four at once, each a different choice.
        io_write(16'h8982, 8'hA7);      // umb=2 ems=2 cms=1 opl2=3
        chk2("opl2 in a full register", eff_opl2, 2'd2);
        chk ("cms in a full register",  eff_cms,  1'b1);
        chk ("ems in a full register",  eff_ems,  1'b0);
        chk ("umb in a full register",  eff_umb,  1'b0);
        io_write(16'h8982, 8'h00);
        chk("cms defers again", eff_cms, 1'b1);

        // ---- video -----------------------------------------------------------
        io_write(16'h8983, 8'h01); chk("vga13 1 remains off", eff_vga13, 1'b0);
        io_write(16'h8983, 8'h02); chk("vga13 2 enables",    eff_vga13, 1'b1);
        io_write(16'h8983, 8'h03); chk("vga13 3 is reserved/off", eff_vga13, 1'b0);
        io_write(16'h8983, 8'h00); chk("vga13 0 disables again", eff_vga13, 1'b0);

        // A BIOS warm-boot marker clears only the extension VGATSR enabled. A
        // launcher may have left other overrides in place, and a warm boot
        // must not silently rewrite them.
        io_write(16'h8981, 8'h0A);
        io_write(16'h8983, 8'h02);
        @(negedge clock); clear_vga13 = 1'b1;
        @(posedge clock);
        @(negedge clock); clear_vga13 = 1'b0;
        chk("warm reset disables vga13", eff_vga13, 1'b0);
        if (reg_vid !== 8'h00) fail("warm reset did not clear video register");
        if (reg_cpu !== 8'h0A) fail("warm reset disturbed another override");
        io_write(16'h8981, 8'h00);

        // ---- input ------------------------------------------------------------
        io_write(16'h8984, 8'h01);
        chk("joy1 analog clears digital", eff_joy1_digital, 1'b0);
        chk("joy1 analog clears disable", eff_joy1_disable, 1'b0);
        io_write(16'h8984, 8'h02);
        chk("joy1 digital sets digital",  eff_joy1_digital, 1'b1);
        chk("joy1 digital clears disable", eff_joy1_disable, 1'b0);
        io_write(16'h8984, 8'h03);
        chk("joy1 disabled sets disable", eff_joy1_disable, 1'b1);

        io_write(16'h8984, 8'h0C);      // joy2 = 3, disabled
        chk("joy2 disabled sets disable", eff_joy2_disable, 1'b1);
        chk("joy1 defers while joy2 is set", eff_joy1_digital, 1'b1);

        io_write(16'h8984, 8'h10); chk("swap 1 is normal",   eff_joy_swap, 1'b0);
        io_write(16'h8984, 8'h20); chk("swap 2 swaps",       eff_joy_swap, 1'b1);
        io_write(16'h8984, 8'h40); chk("joy sync 1 is off",  eff_joy_sync, 1'b0);
        io_write(16'h8984, 8'h80); chk("joy sync 2 is on",   eff_joy_sync, 1'b1);
        io_write(16'h8984, 8'h00);

        // ---- MIDI --------------------------------------------------------------
        io_write(16'h8985, 8'h01); chk("mt32 1 selects MT-32",       eff_mt32_gm, 1'b0);
        io_write(16'h8985, 8'h02); chk("mt32 2 selects General MIDI", eff_mt32_gm, 1'b1);
        io_write(16'h8985, 8'h00); chk("mt32 defers again",          eff_mt32_gm, 1'b1);

        io_write(16'h8985, 8'h04); chk("mpu401 1 enables",  eff_mpu401, 1'b1);
        io_write(16'h8985, 8'h08); chk("mpu401 2 disables", eff_mpu401, 1'b0);
        osd_mpu401 = 1'b0;
        io_write(16'h8985, 8'h04); chk("mpu401 1 enables over a clear OSD", eff_mpu401, 1'b1);
        io_write(16'h8985, 8'h00); chk("mpu401 0 defers to the OSD", eff_mpu401, 1'b0);
        osd_mpu401 = 1'b1;
        io_write(16'h8985, 8'h00);

        // ---- Sound Blaster IRQ and Tandy sound, in their own register --------------
        // Sound Blaster IRQ: 1=IRQ5, 2=IRQ7, with zero following the OSD.
        io_write(16'h8986, 8'h10); chk3("sb irq 1 selects IRQ5", eff_sb_irq, 3'd5);
        io_write(16'h8986, 8'h20); chk3("sb irq 2 selects IRQ7", eff_sb_irq, 3'd7);
        io_write(16'h8986, 8'h30); chk3("sb irq 3 falls back to OSD", eff_sb_irq, 3'd5);
        osd_sb_irq = 3'd7;
        io_write(16'h8986, 8'h00); chk3("sb irq 0 follows IRQ7 OSD", eff_sb_irq, 3'd7);
        osd_sb_irq = 3'd5;

        // ---- Tandy sound, in the same register --------------------------------------
        // Tandy follows the current OSD order: 1=Disabled, 2=Enabled, with
        // zero deferring to the menu. Sound Blaster, and the rule that it and the C/MS cannot both be
        // on: they collide on 226h/227h. The OSD offers one three-way
        // choice so it cannot ask for both, but these two XTEGACTL fields
        // are independent and a program can. The Sound Blaster wins.
        io_write(16'h8986, 8'h00);
        osd_sb = 1'b0; osd_cms = 1'b1;
        #1; chk("sb 0 defers to the OSD",     eff_sb,  1'b0);
        chk("cms keeps 220h with no sb",      eff_cms, 1'b1);
        io_write(16'h8986, 8'h04); chk("sb 1 enables",  eff_sb,  1'b1);
        chk("sb takes 220h from the cms",     eff_cms, 1'b0);
        io_write(16'h8986, 8'h08); chk("sb 2 disables", eff_sb,  1'b0);
        chk("cms gets 220h back",             eff_cms, 1'b1);
        io_write(16'h8986, 8'h00);
        osd_sb = 1'b1;
        #1; chk("sb 0 follows the OSD",       eff_sb,  1'b1);
        chk("osd sb also excludes the cms",   eff_cms, 1'b0);
        build_sb = 1'b0;
        #1; chk("no sb in the build, no sb",  eff_sb,  1'b0);
        chk("and the cms keeps 220h",         eff_cms, 1'b1);
        build_sb = 1'b1; osd_sb = 1'b0;
        #1;

        io_write(16'h8986, 8'h00); chk("tandy 0 defers to disabled OSD", eff_tandy, 1'b0);
        osd_tandy = 1'b1;
        #1; chk("tandy 0 follows enabled OSD", eff_tandy, 1'b1);
        io_write(16'h8986, 8'h01); chk("tandy 1 disables", eff_tandy, 1'b0);
        io_write(16'h8986, 8'h02); chk("tandy 2 enables",  eff_tandy, 1'b1);
        io_write(16'h8986, 8'h00); chk("tandy 0 defers to enabled OSD", eff_tandy, 1'b1);

        // With the chip compiled out the build says no, and the field must not
        // be able to conjure hardware that is not there.
        build_tandy = 1'b0;
        io_write(16'h8986, 8'h00); chk("tandy 0 follows a build without the chip", eff_tandy, 1'b0);
        io_write(16'h8986, 8'h02); chk("tandy 2 cannot enable missing hardware", eff_tandy, 1'b0);
        build_tandy = 1'b1; osd_tandy = 1'b0;
        io_write(16'h8986, 8'h00);

        // ---- readback ------------------------------------------------------------
        io_write(16'h8981, 8'h12);
        io_read (16'h8981, rd);
        if (rd !== 8'h12) fail($sformatf("cpu register read %02h expected 12", rd));
        io_write(16'h8984, 8'h5A);
        io_read (16'h8984, rd);
        if (rd !== 8'h5A) fail($sformatf("input register read %02h expected 5A", rd));

        // ---- CRT geometry ----------------------------------------------------------
        // 8987h and 8988h used to be reserved. They now carry the screen
        // geometry a launcher sets before handing over to a game.
        io_write(16'h8987, 8'h00);
        io_write(16'h8988, 8'h00);
        #1;
        chk4("crt h defers to the OSD", eff_crt_h, 4'd5);
        chk3("crt v defers to the OSD", eff_crt_v, 3'd3);
        chk3("vsync defers to the OSD", eff_vsync_w, 3'd2);
        chk3("hsync defers to the OSD", eff_hsync_w, 3'd4);

        // Bit 7 is the override. Without it a zero offset would be
        // indistinguishable from "leave it to the OSD".
        io_write(16'h8987, 8'h0A);
        #1;
        chk4("crt h ignores a register with no override", eff_crt_h, 4'd5);
        io_write(16'h8987, 8'h8A);
        #1;
        chk4("crt h takes the override", eff_crt_h, 4'd10);
        chk3("crt v takes the override", eff_crt_v, 3'd0);
        io_write(16'h8987, 8'hF0);
        #1;
        chk4("crt h zero is a real offset", eff_crt_h, 4'd0);
        chk3("crt v reads its own field",   eff_crt_v, 3'd7);

        // A non-zero register field overrides the OSD; clearing it defers
        // back to the OSD values.
        io_write(16'h8988, 8'h2B);
        #1;
        chk3("vsync width from the register", eff_vsync_w, 3'd3);
        chk3("hsync width from the register", eff_hsync_w, 3'd5);
        io_read (16'h8988, rd);
        if (rd !== 8'h2B) fail($sformatf("sync register read %02h expected 2B", rd));
        io_write(16'h8987, 8'h00);
        io_write(16'h8988, 8'h00);
        chk3("vsync returns to the OSD", eff_vsync_w, 3'd2);
        chk3("hsync returns to the OSD", eff_hsync_w, 3'd4);

        // ---- the block keeps to itself ------------------------------------------------
        // 8888h is the retired port, and any of its neighbours would land on the
        // on-board decoder.  Nothing here may answer for them.
        @(negedge clock);
        address = 16'h8888; io_read_n = 1'b0;
        #1 if (output_enable) fail("answered for the retired 8888h port");
        io_read_n = 1'b1;

        @(negedge clock);
        address = 16'h8990; io_read_n = 1'b0;
        #1 if (output_enable) fail("answered past the end of the block");
        io_read_n = 1'b1;

        // A write must not be taken while the DMA controller owns the bus.
        io_write(16'h8983, 8'h02);
        @(negedge clock);
        address_enable_n = 1'b1;
        io_write(16'h8983, 8'h01);
        address_enable_n = 1'b0;
        chk("ignored a write made during a DMA cycle", eff_vga13, 1'b1);

        // ---- reset returns every override to its default ----------------------------------
        io_write(16'h8982, 8'hAA);
        reset = 1'b1;
        repeat (2) @(posedge clock);
        reset = 1'b0;
        chk("reset returns cms to the OSD", eff_cms, 1'b1);
        chk("reset returns umb to the OSD", eff_umb, 1'b1);
        chk("reset returns tandy to the OSD", eff_tandy, 1'b0);
        chk3("reset returns sb irq to the OSD", eff_sb_irq, 3'd5);
        chk("reset disables vga13", eff_vga13, 1'b0);
        io_read(16'h8982, rd);
        if (rd !== 8'h00) fail($sformatf("expansion register survived reset as %02h", rd));

        if (errors == 0)
            $display("RESULT: PASS (XTEGACTL decodes clear of the on-board block; VGA13 starts disabled)");
        else
            $display("RESULT: FAIL (%0d checks)", errors);
        $finish;
    end

endmodule
