`timescale 1ns / 1ps

module system
	(
		 input clk_100,
		 input clk_vga,
		 input clk_25,
		 input clk_sys,
		 input clk_sys2,
		 input clk_cpu,
		 input disable_splashscreen,
		 input IRQ0,

		 input reset,
		 output wire de_o,
		 
		 output wire [5:0]VGA_R,
		 output wire [5:0]VGA_G,
		 output wire [5:0]VGA_B,
		 output wire VGA_HSYNC,
		 output wire VGA_VSYNC,

		 output wire HBlank,
		 output wire VBlank,

		 input PS2_CLK1_I,
		 output PS2_CLK1_O,
		 input PS2_CLK2_I,
		 output PS2_CLK2_O,
		 input PS2_DATA1_I,
		 output PS2_DATA1_O,
		 input PS2_DATA2_I,
		 output PS2_DATA2_O,
		 output LED,
		 //output reg SD_n_CS = 1,
		 //output wire SD_DI,
		 //output reg SD_CK = 0,
		 //input SD_DO

		input ioctl_download,
		input ioctl_index,
		input ioctl_wr,
		input ioctl_addr,
		input ioctl_dout	
    );

	wire [7:0] DOUT;
	wire [20:0] ADDR;
	wire IORQ;
	wire WR_n;
	wire RD_n;
	wire INTA;
	wire IOM;

	reg [4:0]rstcount = 0;
	reg [2:0] reset2 = 1'b000;
	
	reg [1:0] speaker_on = 0;	
	reg [24:0] splash_cnt = 0;
	reg [3:0] splash_cnt2 = 0;
	reg splashscreen = 1;

	wire [7:0] CPU_DIN;

	wire VRAM_ENABLE;
	wire [18:0] VRAM_ADDR;
	wire [7:0] VRAM_DOUT;

	wire [7:0]TIMER_DOUT;
	wire [7:0]PIC_DOUT;
	wire [7:0]KB_DOUT;

	wire CRTC_OE;
	wire [7:0] CRTC_DOUT;

	reg test_led = 0;
	assign LED = test_led;
	
	//assign LED = ~SD_n_CS;

	wire TIMER_OE = ADDR[15:2] == 14'b00000000010000;	//   40h..43h
	//wire SD_OE_LO = ADDR[15:0] == 16'h0300;
	//wire SD_OE_HI = ADDR[15:0] == 16'h0301;
	wire SPEAKER_PORT = ADDR[15:0] == 16'h0061;
	wire LED_PORT = ADDR[15:0] == 16'h03bc;
	wire KB_OE = ADDR[15:4] == 12'h006 && {ADDR[3], ADDR[1:0]} == 3'b000; // 60h, 64h
	//wire PIC_OE = ADDR[15:8] == 8'h00 && ADDR[6:1] == 6'b010000;	// 20h, 21h, a0h, a1h
	wire PIC_OE = ADDR[15:8] == 8'h00 && ADDR[6:0] == 7'b0100001;	// 21h, a1h

    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.
    parameter MDA_70HZ = 0;

    wire[3:0] vga_video;
	 wire[3:0] video;

    // wire composite_on;
    wire thin_font;

    wire[5:0] vga_red;
    wire[5:0] vga_green;
    wire[5:0] vga_blue;

	// Composite mode switch
    //assign composite_on = switch3; (TODO: Test in next version, from the original Graphics Gremlin sources)

    // Thin font switch (TODO: switchable with Keyboard shortcut)
	 assign thin_font = 1'b0; // Default: No thin font

    // CGA digital to analog converter
    cga_vgaport vga (
        .clk(clk_vga),
//      .video(vga_video),		  
        .video(video),		  //Mister Test without Scandouble
        .red(VGA_R),
        .green(VGA_G),
        .blue(VGA_B)
    );    

	cga cga1 (
        .clk(clk_vga),
		.bus_a(ADDR[15:0]),
		.bus_ior_l(RD_n),
        .bus_iow_l(WR_n),
        .bus_memr_l(1'd0),
        .bus_memw_l(1'd0),
        .bus_d(CPU_DIN),
        .bus_out(CRTC_DOUT),
        .bus_dir(CRTC_OE),
        .bus_aen(~IOM),
        .ram_we_l(VRAM_ENABLE),
        .ram_a(VRAM_ADDR),
        .ram_d(VRAM_DOUT),
//      .dbl_hsync(VGA_HSYNC), 
		.hsync(VGA_HSYNC), //Mister Test without Scandouble
        .vsync(VGA_VSYNC),
		.de_o(de_o),

		.hdisp(HBlank),
		.vdisp(VBlank),

        .video(video),
        //.dbl_video(vga_video),
        .comp_video(comp_video),
		.splashscreen(splashscreen),
        .thin_font(thin_font)
    );

	defparam cga1.BLINK_MAX = 24'd4772727;

	parameter crtc_addr_b8000 = 6'b10111; // B8000 - BFFFF (32 KB)	
	parameter bios_addr_f0000 = 5'b1111; // F0000 - FFFFF (64 KB)
	parameter ram_addr_00000 = 3'b00; // 00000 - 3FFFF (256 KB)
	wire CRTCVRAM = (ADDR[19:15] == crtc_addr_b8000);	
	wire BIOSROM = (ADDR[19:16] == bios_addr_f0000);
	wire RAM = (ADDR[19:18] == ram_addr_00000);

	wire [7:0] bios_cpu_dout;
	wire [7:0] ram_cpu_dout;
	wire [7:0] vram_cpu_dout;
	wire [7:0] ibm_cpu_dout;

	//reg [7:0]SDI;
	//assign SD_DI = CPU_DIN[7];

	assign CPU_DIN = IOM ?
							 (
							 SPEAKER_PORT && ~RD_n ? {6'd0, speaker_on} :							 
							 //SD_OE_HI && ~RD_n ? SDI :
							 //SD_OE_LO && ~RD_n ? {8'b1x000000} :
							 KB_OE && ~RD_n ? KB_DOUT :
							 ~INTA ? PIC_IVECT :
							 TIMER_OE && ~RD_n ? TIMER_DOUT :
							 PIC_OE && ~RD_n ? PIC_DOUT :
							 CRTC_OE && ~RD_n ? CRTC_DOUT : DOUT
							 )

							 :

							 (
							 BIOSROM && ~RD_n ? bios_cpu_dout :
							 RAM && ~RD_n ? ram_cpu_dout :
							 CRTCVRAM && ~RD_n ? vram_cpu_dout : 8'hZZ
							 );

	bios bios
	(
	  .clka(clk_sys), // clk_sys or clk_cpu?
	  .ena(~IOM && BIOSROM),
	  .wea(~WR_n),
	  .addra(ADDR[15:0]),
	  .dina(DOUT),
	  .douta(bios_cpu_dout)
	);

	dpr #(.AW(18)) ram
	(
		.clock(clk_sys),
		// Port A
		.ce1(~IOM && RAM),
		.we1(~WR_n),
		.di1(DOUT),
		.do1(ram_cpu_dout),
		.a1(ADDR[17:0]),
		// Port B
		.ce2(),
		.we2(),
		.di2(),
		.do2(),
		.a2()
	);

	vram vram
	(
	  .clka(clk_sys), // clk_sys or clk_cpu?
	  .ena(~IOM && CRTCVRAM),	  
	  .wea(~WR_n),
	  .addra(ADDR[14:0]),
	  .dina(DOUT),
	  .douta(vram_cpu_dout),
	  .clkb(clk_vga),
	  .web(1'b0),
	  .enb(VRAM_ENABLE),
	  .addrb(VRAM_ADDR[14:0]),
	  .dinb(8'h0),
	  .doutb(VRAM_DOUT)
	);
	
	always @ (posedge clk_sys) begin
	
		if (splashscreen) begin
			if (disable_splashscreen)
				splashscreen <= 0;
			else if(splash_cnt2 == 5) // 5 seconds delay
				splashscreen <= 0;
			else if (splash_cnt == 14318000) begin // 1 second at 14.318Mhz
					splash_cnt2 <= splash_cnt2 + 1;				
					splash_cnt <= 0;
				end
			else
				splash_cnt <= splash_cnt + 1;			
		end
	
	end
	

	always @ (posedge clk_cpu) begin
		reset2 <= reset2 < 3'b010 ? reset2 + 1'b1 : reset2;		
		
		if(KB_RST) rstcount <= 0;
		else if(~rstcount[4]) rstcount <= rstcount + 1;

		if(IOM && ~WR_n && SPEAKER_PORT) 
			speaker_on <= CPU_DIN[1:0];			

		if(IOM && ~WR_n && LED_PORT)
			test_led <= CPU_DIN[0];

		// SD

		//SD_CK <= IOM && ~WR_n && SD_OE_LO;

		//if(IOM && ~WR_n && SD_OE_HI)
		//	SD_n_CS <= ~CPU_DIN[0]; // SD chip select

		//if(IOM && ~WR_n && SD_OE_LO)
		//	SDI <= {SDI[6:0], SD_DO};	

	end

	wire I_KB;
	wire I_MOUSE;
	wire KB_RST;
	KB_Mouse_8042 KB_Mouse
	(
		 .CS(IOM && KB_OE), // 60h, 64h
		 .WR(~WR_n),
		 .cmd(ADDR[2]), // 64h
		 .din(CPU_DIN),
		 .dout(KB_DOUT),
		 .clk(clk_sys2),  // clk_sys / 2 -> 7.318Mhz ... or clk_cpu?
		 .I_KB(I_KB),
		 .I_MOUSE(I_MOUSE),
		 .CPU_RST(KB_RST),
	    .PS2_CLK1_I(PS2_CLK1_I),
		 .PS2_CLK1_O(PS2_CLK1_O),
	    .PS2_CLK2_I(PS2_CLK2_I),
		 .PS2_CLK2_O(PS2_CLK2_O),
		 .PS2_DATA1_I(PS2_DATA1_I),
		 .PS2_DATA1_O(PS2_DATA1_O),
		 .PS2_DATA2_I(PS2_DATA2_I),
		 .PS2_DATA2_O(PS2_DATA2_O)
	);

	wire [7:0]PIC_IVECT;
	wire INT;
	wire timer_int;
	wire I_COM1; 
	PIC_8259 PIC 
	(
		 .CS(IOM && PIC_OE), // 20h, 21h
		 .WR(~WR_n),
		 .din(CPU_DIN),
		 .dout(PIC_DOUT),
		 .ivect(PIC_IVECT),
		 .clk(clk_cpu),
		 .INT(INT),
		 .IACK(~INTA),
		 .I({I_MOUSE, 1'b0, I_KB, IRQ0 & timer_int})
    );

	wire timer_spk;
	timer_8253 timer 
	(
		 .CS(IOM && TIMER_OE),
		 .WR(~WR_n), 
		 .addr(ADDR[1:0]), 
		 .din(CPU_DIN),
		 .dout(TIMER_DOUT), 
		 .CLK_25(clk_25), // Modify module to be able to use clk_sys / 12 instead clk_25
		 .clk(clk_cpu),
		 .gate2(speaker_on[0]),
		 .out0(timer_int), 
		 .out2(timer_spk)
   );	

	i8088 B1(
	  .CORE_CLK(clk_100),
	  .CLK(clk_cpu),

	  .RESET(reset || splashscreen),
	  .READY(1'b1),	  
	  .NMI(1'b0),
	  .INTR(INT),
	  .INTA_n(INTA),
	  .addr(ADDR[19:0]),
	  .dout(DOUT),
	  .din(CPU_DIN),
	  .IOM(IOM),
	  .RD_n(RD_n),
	  .WR_n(WR_n)
	);

endmodule