// Detect the IBM PC/XT warm-boot marker in the BIOS Data Area.
//
// IBM-compatible BIOSes traditionally write 1234h to 0040:0072 before
// restarting.  On an 8088 this is two byte writes (34h at 0472h followed by
// 12h at 0473h); the 8086 path can issue the same value as one word write.
// This deliberately observes the memory bus rather than the keyboard, so a
// program that masks Ctrl+Alt+Del does not cause a false warm-boot clear.
`default_nettype none

module warm_boot_marker_detector (
    input  logic        clock,
    input  logic        reset,
    input  logic [19:0] address,
    input  logic        address_enable_n,
    input  logic        memory_write_n,
    input  logic [7:0]  byte_data,
    input  logic        word_write_request,
    input  logic [15:0] word_data,
    output logic        warm_boot_event
);

    localparam logic [19:0] WARM_BOOT_LOW_ADDRESS  = 20'h00472;
    localparam logic [19:0] WARM_BOOT_HIGH_ADDRESS = 20'h00473;

    logic write_active_d;
    logic expect_high_byte;

    wire write_active = ~address_enable_n & ~memory_write_n;
    wire write_event  = write_active & ~write_active_d;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            write_active_d  <= 1'b0;
            expect_high_byte <= 1'b0;
            warm_boot_event  <= 1'b0;
        end
        else begin
            write_active_d <= write_active;
            warm_boot_event <= 1'b0;

            if (write_event) begin
                // The 8086 private word path presents both bytes together.
                if (word_write_request &&
                    (address == WARM_BOOT_LOW_ADDRESS) &&
                    (word_data == 16'h1234)) begin
                    warm_boot_event  <= 1'b1;
                    expect_high_byte <= 1'b0;
                end
                // The normal 8088 path writes the word little-endian.
                else if (!word_write_request && expect_high_byte &&
                         (address == WARM_BOOT_HIGH_ADDRESS) &&
                         (byte_data == 8'h12)) begin
                    warm_boot_event  <= 1'b1;
                    expect_high_byte <= 1'b0;
                end
                else if (!word_write_request &&
                         (address == WARM_BOOT_LOW_ADDRESS) &&
                         (byte_data == 8'h34)) begin
                    expect_high_byte <= 1'b1;
                end
                else begin
                    expect_high_byte <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
