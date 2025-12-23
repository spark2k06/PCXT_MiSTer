module splash_rom
(
    input  wire [11:0] addr,
    output reg  [7:0]  data
);

    reg [7:0] mem[0:4095];
    integer i;

    initial begin
        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 8'h00;
        $readmemh("splash.hex", mem);
    end

    always @* data = mem[addr];

endmodule
