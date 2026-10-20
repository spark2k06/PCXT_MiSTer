//
// Two masters of the CPU memory port (chipset clock domain) on one
// sdram_xbridge: cpu_mem_port, and the video memory frontend of an EGA card
// whose CPU window is not served by cpu_mem_port.
//
// They never ask at the same time - both are the one CPU bus cycle - but one
// may start while the other's posted write is still crossing, so the bridge's
// busy serialises them, and its done is given to the master that started the
// transaction in flight, not to both: the other one must not mistake it for its
// own.
//
module sdram_txn_mux (
    input  logic        clock,
    input  logic        reset,

    // master 0 (cpu_mem_port) and master 1 (video frontend)
    input  logic        a0_start,
    input  logic        a0_we,
    input  logic [23:0] a0_addr,
    input  logic [1:0]  a0_len,
    input  logic [63:0] a0_wdata,
    input  logic [7:0]  a0_wbe,
    output logic        a0_done,

    input  logic        a1_start,
    input  logic        a1_we,
    input  logic [23:0] a1_addr,
    input  logic [1:0]  a1_len,
    input  logic [63:0] a1_wdata,
    input  logic [7:0]  a1_wbe,
    output logic        a1_done,

    // to sdram_xbridge
    output logic        m_start,
    output logic        m_we,
    output logic [23:0] m_addr,
    output logic [1:0]  m_len,
    output logic [63:0] m_wdata,
    output logic [7:0]  m_wbe,
    input  logic        m_busy,
    input  logic        m_done
);
    logic owner;                       // master of the transaction in flight

    assign m_start = a0_start | a1_start;
    assign m_we    = a1_start ? a1_we    : a0_we;
    assign m_addr  = a1_start ? a1_addr  : a0_addr;
    assign m_len   = a1_start ? a1_len   : a0_len;
    assign m_wdata = a1_start ? a1_wdata : a0_wdata;
    assign m_wbe   = a1_start ? a1_wbe   : a0_wbe;

    always_ff @(posedge clock) begin
        if (reset)
            owner <= 1'b0;
        else if (m_start && !m_busy)
            owner <= a1_start;
    end

    assign a0_done = m_done & ~owner;
    assign a1_done = m_done &  owner;
endmodule
