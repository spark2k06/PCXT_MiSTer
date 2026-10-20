// What the XTEGACTL registers mean, and how they combine with the OSD.
//
// Every field encodes 0 as "leave it to the OSD" and 1..N as the N choices in
// the same order the menu lists them.  So the power-on state of all zeroes is
// plain OSD behaviour, a program overrides only what it cares about, and a
// setting left behind by an earlier program cannot quietly capture an option
// nobody meant to touch.  It also means the tool never has to read the menu
// back to leave something alone: writing zero is how you say "not mine".
//
// Purely combinational, and kept apart from the port block so it can sit at
// the top level where the OSD status is. Besides driving the core, it emits a
// compact read-only snapshot for XTEGACTL status, so DOS sees the effective
// value and not merely the raw override register.

`default_nettype none

module xtegactl_resolve (
    // Raw registers from the port block.
    input  wire  [7:0] reg_cpu,
    input  wire  [7:0] reg_exp,
    input  wire  [7:0] reg_vid,
    input  wire  [7:0] reg_inp,
    input  wire  [7:0] reg_midi,
    input  wire  [7:0] reg_exp2,

    // What the OSD currently asks for.
    input  wire  [1:0] osd_speed,        // 0=4.77  1=7.16  2=9.54  3=Max
    input  wire        osd_fake286,
    input  wire  [1:0] osd_opl2,         // 0=388h  1=388h+228h  2=off
    input  wire        osd_cms,
    input  wire        osd_sb,
    input  wire  [2:0] osd_sb_irq,
    input  wire        osd_ems,
    input  wire        osd_umb,
    input  wire        osd_joy1_digital,
    input  wire        osd_joy1_disable,
    input  wire        osd_joy2_digital,
    input  wire        osd_joy2_disable,
    input  wire        osd_joy_sync,
    input  wire        osd_joy_swap,
    input  wire        osd_mt32_gm,
    input  wire        osd_tandy,
    input  wire        osd_mpu401,
    input  wire  [7:0] reg_crt,
    input  wire  [7:0] reg_sync,
    input  wire  [3:0] osd_crt_h,
    input  wire  [2:0] osd_crt_v,
    input  wire  [2:0] osd_vsync_w,
    input  wire  [2:0] osd_hsync_w,
    input  wire        build_sb,
    // Tandy sound defers to the OSD like the other runtime fields. Whether the
    // SN76489 exists at all is still a build-time choice, so this separately
    // gates eff_tandy the same way build_sb gates eff_sb: hardware that was
    // not built can never be switched on, no matter what the menu or a program
    // asks for.
    input  wire        build_tandy,

    // What the machine should actually run on.
    output wire  [1:0] eff_speed,
    output wire        eff_fake286,
    output wire  [1:0] eff_opl2,
    output wire        eff_cms,
    output wire        eff_sb,
    output wire  [2:0] eff_sb_irq,
    output wire        eff_ems,
    output wire        eff_umb,
    output wire        eff_vga13,
    output wire        eff_joy1_digital,
    output wire        eff_joy1_disable,
    output wire        eff_joy2_digital,
    output wire        eff_joy2_disable,
    output wire        eff_joy_sync,
    output wire        eff_joy_swap,
    output wire        eff_mt32_gm,
    output wire        eff_tandy,
    output wire        eff_mpu401,
    output wire  [3:0] eff_crt_h,
    output wire  [2:0] eff_crt_v,
    output wire  [2:0] eff_vsync_w,
    output wire  [2:0] eff_hsync_w,

    // Effective status bytes, packed as documented by xtegactl.sv. The
    // effective VGA 13h+ bit is included, but has no OSD match bit because
    // VGATSR owns that enable rather than an OSD option.
    output wire [39:0] status_effective,
    // Match bits: speed, fake FLAGS, OPL2, Audio 220h, EMS, UMB, joystick 1,
    // joystick 2, swap, joy sync, MT32-pi, MPU-401, Tandy, SB IRQ, CRT H,
    // CRT V, VSync and HSync, respectively.
    output wire [17:0] status_osd_match
);

    // Named so the resolution below reads as the table in the header rather
    // than as bit arithmetic.
    wire [2:0] f_speed   = reg_cpu[2:0];
    wire [1:0] f_fake286 = reg_cpu[4:3];
    wire [1:0] f_opl2    = reg_exp[1:0];
    wire [1:0] f_cms     = reg_exp[3:2];
    wire [1:0] f_ems     = reg_exp[5:4];
    wire [1:0] f_umb     = reg_exp[7:6];
    wire [1:0] f_vga13   = reg_vid[1:0];
    wire [1:0] f_joy1    = reg_inp[1:0];
    wire [1:0] f_joy2    = reg_inp[3:2];
    wire [1:0] f_swap    = reg_inp[5:4];
    wire [1:0] f_sync    = reg_inp[7:6];
    wire [1:0] f_mt32    = reg_midi[1:0];
    wire [1:0] f_mpu401  = reg_midi[3:2];
    wire [1:0] f_tandy   = reg_exp2[1:0];
    wire [1:0] f_sb      = reg_exp2[3:2];
    wire [1:0] f_sb_irq  = reg_exp2[5:4];

    // Screen geometry, meant to be set by a launcher just before it hands
    // over to a game - centring the picture is per-program work, not a
    // property of the machine.
    //
    // The offsets cannot use the usual "zero defers to the OSD" rule,
    // because zero is a real offset, so they carry an explicit override
    // bit instead. The sync widths use zero to defer to the OSD and a
    // non-zero register value as a per-program override.
    wire [3:0] f_crt_h   = reg_crt[3:0];
    wire [2:0] f_crt_v   = reg_crt[6:4];
    wire       f_crt_ovr = reg_crt[7];
    wire [2:0] f_vsync_w = reg_sync[2:0];
    wire [2:0] f_hsync_w = reg_sync[5:3];

    // Speed is the one field wider than two bits, because it picks between
    // four choices rather than three.  Values above Max are not choices, so
    // they read as "leave it to the OSD" rather than aliasing onto a speed.
    wire speed_override = (f_speed >= 3'd1) & (f_speed <= 3'd4);
    assign eff_speed = speed_override ? (f_speed[1:0] - 2'd1) : osd_speed;

    // 1 selects the first menu entry, 2 the second.
    assign eff_fake286 = (f_fake286 == 2'd0) ? osd_fake286  : (f_fake286 == 2'd2);
    assign eff_opl2    = (f_opl2    == 2'd0) ? osd_opl2     : (f_opl2 - 2'd1);
    // The Sound Blaster and the C/MS share 220h and collide on 226h/227h -
    // one puts its DSP reset there, the other its detection register - so
    // only one of them may answer. The OSD offers them as a single
    // three-way choice and so cannot ask for both, but the XTEGACTL fields
    // are independent and a program can set either. The Sound Blaster wins
    // that tie, because a program that went out of its way to ask for one
    // is the better guess at intent than a default left enabled.
    wire cms_selected  = (f_cms == 2'd0) ? osd_cms : (f_cms == 2'd1);
    assign eff_sb      = build_sb & ((f_sb == 2'd0) ? osd_sb : (f_sb == 2'd1));
    // IRQ 5 is the OSD default. As with the other fields, zero defers to the
    // menu and an invalid value must not alias onto a real choice.
    assign eff_sb_irq  = (f_sb_irq == 2'd0) ? osd_sb_irq :
                         (f_sb_irq == 2'd1) ? 3'd5 :
                         (f_sb_irq == 2'd2) ? 3'd7 : osd_sb_irq;
    assign eff_cms     = cms_selected & ~eff_sb;
    assign eff_ems     = (f_ems     == 2'd0) ? osd_ems      : (f_ems   == 2'd1);
    assign eff_umb     = (f_umb     == 2'd0) ? osd_umb      : (f_umb   == 2'd1);
    // VGA 13h+ deliberately has no OSD master switch. The extension starts
    // absent after reset and VGATSR selects value 2 (vga13) before it installs
    // its INT 10h hook. Keep value 1 as the legacy novga13 spelling, so old
    // launchers still explicitly disable the extension.
    assign eff_vga13   = (f_vga13 == 2'd2);
    assign eff_joy_swap= (f_swap    == 2'd0) ? osd_joy_swap : (f_swap  == 2'd2);
    assign eff_joy_sync= (f_sync    == 2'd0) ? osd_joy_sync : (f_sync  == 2'd2);
    assign eff_mt32_gm = (f_mt32    == 2'd0) ? osd_mt32_gm  : (f_mt32  == 2'd2);
    assign eff_mpu401  = (f_mpu401  == 2'd0) ? osd_mpu401   : (f_mpu401 == 2'd1);
    // build_tandy gates eff_tandy the same way build_sb gates eff_sb above:
    // hardware that was not built can never be switched on, regardless of
    // what the OSD default or a program's override say.
    assign eff_tandy   = build_tandy & ((f_tandy == 2'd0) ? osd_tandy : (f_tandy == 2'd2));

    assign eff_crt_h   = f_crt_ovr ? f_crt_h : osd_crt_h;
    assign eff_crt_v   = f_crt_ovr ? f_crt_v : osd_crt_v;
    assign eff_vsync_w = (f_vsync_w == 3'd0) ? osd_vsync_w : f_vsync_w;
    assign eff_hsync_w = (f_hsync_w == 3'd0) ? osd_hsync_w : f_hsync_w;

    // Analog, Digital and Disabled are one menu option but two signals: the
    // core carries the stick type and the disable separately.
    assign eff_joy1_digital = (f_joy1 == 2'd0) ? osd_joy1_digital : (f_joy1 == 2'd2);
    assign eff_joy1_disable = (f_joy1 == 2'd0) ? osd_joy1_disable : (f_joy1 == 2'd3);
    assign eff_joy2_digital = (f_joy2 == 2'd0) ? osd_joy2_digital : (f_joy2 == 2'd2);
    assign eff_joy2_disable = (f_joy2 == 2'd0) ? osd_joy2_disable : (f_joy2 == 2'd3);

    // Canonical menu values used by the status snapshot. These are not the
    // raw XTEGACTL encodings: zero is a real first menu choice here, which is
    // what lets the DOS tool print the current value for an OSD-deferred
    // field.
    wire [1:0] effective_audio220 = eff_sb ? 2'd1 : eff_cms ? 2'd0 : 2'd2;
    wire [1:0] effective_joy1 = eff_joy1_disable ? 2'd2 :
                                 eff_joy1_digital ? 2'd1 : 2'd0;
    wire [1:0] effective_joy2 = eff_joy2_disable ? 2'd2 :
                                 eff_joy2_digital ? 2'd1 : 2'd0;
    wire [1:0] osd_audio220 = osd_sb ? 2'd1 : osd_cms ? 2'd0 : 2'd2;
    wire [1:0] osd_joy1 = osd_joy1_disable ? 2'd2 :
                          osd_joy1_digital ? 2'd1 : 2'd0;
    wire [1:0] osd_joy2 = osd_joy2_disable ? 2'd2 :
                          osd_joy2_digital ? 2'd1 : 2'd0;

    // Five compact effective-value bytes:
    //   8989: speed[1:0], fake286[3], OPL2[5:4], Audio 220h[7:6]
    //   898A: EMS[0], UMB[1], VGA13[2], joy1[4:3], joy2[6:5], swap[7]
    //   898B: joy sync[0], MT32[1], MPU[2], Tandy[4:3], SB IRQ7[5]
    //   898C: CRT H[3:0], CRT V[6:4]
    //   898D: VSync[2:0], HSync[5:3]
    assign status_effective[7:0]   = {effective_audio220, eff_opl2, eff_fake286,
                                      1'b0, eff_speed};
    assign status_effective[15:8]  = {eff_joy_swap, effective_joy2,
                                      effective_joy1, eff_vga13, eff_umb, eff_ems};
    assign status_effective[23:16] = {2'b00, (eff_sb_irq == 3'd7),
                                       1'b0, eff_tandy, eff_mpu401,
                                       eff_mt32_gm, eff_joy_sync};
    assign status_effective[31:24] = {1'b0, eff_crt_v, eff_crt_h};
    assign status_effective[39:32] = {2'b00, eff_hsync_w, eff_vsync_w};

    // Compare effective values with the live OSD values, not raw override
    // fields. An explicit override that happens to select the same value as
    // the OSD is therefore still marked as matching, as users expect from a
    // status display. VGA 13h+ is intentionally absent from this mask.
    assign status_osd_match[0]  = (eff_speed == osd_speed);
    assign status_osd_match[1]  = (eff_fake286 == osd_fake286);
    assign status_osd_match[2]  = (eff_opl2 == osd_opl2);
    assign status_osd_match[3]  = (effective_audio220 == osd_audio220);
    assign status_osd_match[4]  = (eff_ems == osd_ems);
    assign status_osd_match[5]  = (eff_umb == osd_umb);
    assign status_osd_match[6]  = (effective_joy1 == osd_joy1);
    assign status_osd_match[7]  = (effective_joy2 == osd_joy2);
    assign status_osd_match[8]  = (eff_joy_swap == osd_joy_swap);
    assign status_osd_match[9]  = (eff_joy_sync == osd_joy_sync);
    assign status_osd_match[10] = (eff_mt32_gm == osd_mt32_gm);
    assign status_osd_match[11] = (eff_mpu401 == osd_mpu401);
    assign status_osd_match[12] = (eff_tandy == (build_tandy & osd_tandy));
    assign status_osd_match[13] = (eff_sb_irq == osd_sb_irq);
    assign status_osd_match[14] = (eff_crt_h == osd_crt_h);
    assign status_osd_match[15] = (eff_crt_v == osd_crt_v);
    assign status_osd_match[16] = (eff_vsync_w == osd_vsync_w);
    assign status_osd_match[17] = (eff_hsync_w == osd_hsync_w);

endmodule

`default_nettype wire
