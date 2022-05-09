
module i8088
  (
    input               CORE_CLK,

    input               CLK,
    input               RESET,

    input               READY,
    input               INTR,
    input               NMI,

    output reg [19:0]   addr,
    output reg [7:0]    dout,
    input [7:0]         din,

    output              ALE,
    output              INTA_n,
    output              RD_n,
    output              WR_n,
    output              IOM,
    output              DTR,
    output              DEN

  );

//------------------------------------------------------------------------



// Internal Signals

reg  t_biu_lock_n_d;
wire t_eu_prefix_lock;
wire t_eu_flag_i;
wire t_biu_lock_n;
wire t_pfq_empty;
wire t_biu_done;
wire t_biu_clk_counter_zero;
wire t_biu_ad_oe;
wire t_biu_nmi_caught;
wire t_biu_nmi_debounce;
wire t_biu_intr;
wire [19:0] t_biu_ad_out;
wire [7:0]  t_biu_ad_in;
wire [2:0]  t_s2_s0_out;
wire [15:0] t_eu_biu_command;
wire [15:0] t_eu_biu_dataout;
wire [15:0] t_eu_register_r3;
wire [7:0]  t_pfq_top_byte;
wire [15:0] t_pfq_addr_out;
wire [15:0] t_biu_register_es;
wire [15:0] t_biu_register_ss;
wire [15:0] t_biu_register_cs;
wire [15:0] t_biu_register_ds;
wire [15:0] t_biu_register_rm;
wire [15:0] t_biu_register_reg;
wire [15:0] t_biu_return_data;

always @(posedge CORE_CLK) begin

  if (ALE == 1'b0)
    dout <= t_biu_ad_out[7:0];
  else
    addr <= t_biu_ad_out;

end


//------------------------------------------------------------------------
// BIU Core
//------------------------------------------------------------------------

biu_min                     BIU_CORE
  (
    .CORE_CLK_INT           (CORE_CLK),
    .RESET_INT              (RESET),
    .CLK                    (CLK),
    .READY_IN               (READY),
    .NMI                    (NMI),
    .INTR                   (INTR),
    .INTA_n                 (INTA_n),
    .ALE                    (ALE),
    .RD_n                   (RD_n),
    .WR_n                   (WR_n),
    .IOM                    (IOM),
    .DTR                    (DTR),
    .DEN                    (DEN),
    .AD_OE                  (t_biu_ad_oe),
    .AD_OUT                 (t_biu_ad_out),
    .AD_IN                  (din),
    .EU_BIU_COMMAND         (t_eu_biu_command),
    .EU_BIU_DATAOUT         (t_eu_biu_dataout),
    .EU_REGISTER_R3         (t_eu_register_r3),
    .EU_PREFIX_LOCK         (t_eu_prefix_lock),
    .BIU_DONE               (t_biu_done),
    .BIU_CLK_COUNTER_ZERO   (t_biu_clk_counter_zero),
    .BIU_SEGMENT            ( ),
    .BIU_NMI_CAUGHT         (t_biu_nmi_caught),
    .BIU_NMI_DEBOUNCE       (t_biu_nmi_debounce),
    .BIU_INTR               (t_biu_intr),
    .PFQ_TOP_BYTE           (t_pfq_top_byte),
    .PFQ_EMPTY              (t_pfq_empty),
    .PFQ_ADDR_OUT           (t_pfq_addr_out),
    .BIU_REGISTER_ES        (t_biu_register_es),
    .BIU_REGISTER_SS        (t_biu_register_ss),
    .BIU_REGISTER_CS        (t_biu_register_cs),
    .BIU_REGISTER_DS        (t_biu_register_ds),
    .BIU_REGISTER_RM        (t_biu_register_rm),
    .BIU_REGISTER_REG       (t_biu_register_reg),
    .BIU_RETURN_DATA        (t_biu_return_data)

  );


//------------------------------------------------------------------------
// EU Core
//------------------------------------------------------------------------

mcl86_eu_core               EU_CORE
  (
    .CORE_CLK_INT           (CORE_CLK),
    .RESET_INT              (RESET),
    .TEST_N_INT             (1'b1),
    .EU_BIU_COMMAND         (t_eu_biu_command),
    .EU_BIU_DATAOUT         (t_eu_biu_dataout),
    .EU_REGISTER_R3         (t_eu_register_r3),
    .EU_PREFIX_LOCK         (t_eu_prefix_lock),
    .EU_FLAG_I              (t_eu_flag_i),
    .BIU_DONE               (t_biu_done),
    .BIU_CLK_COUNTER_ZERO   (t_biu_clk_counter_zero),
    .BIU_NMI_CAUGHT         (t_biu_nmi_caught),
    .BIU_NMI_DEBOUNCE       (t_biu_nmi_debounce),
    .BIU_INTR               (t_biu_intr),
    .PFQ_TOP_BYTE           (t_pfq_top_byte),
    .PFQ_EMPTY              (t_pfq_empty),
    .PFQ_ADDR_OUT           (t_pfq_addr_out),
    .BIU_REGISTER_ES        (t_biu_register_es),
    .BIU_REGISTER_SS        (t_biu_register_ss),
    .BIU_REGISTER_CS        (t_biu_register_cs),
    .BIU_REGISTER_DS        (t_biu_register_ds),
    .BIU_REGISTER_RM        (t_biu_register_rm),
    .BIU_REGISTER_REG       (t_biu_register_reg),
    .BIU_RETURN_DATA        (t_biu_return_data)
  );



endmodule
