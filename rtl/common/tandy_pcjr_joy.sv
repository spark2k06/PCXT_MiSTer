// Tandy/PCJr 2 Button Analog Joysticks
// Flandango

module tandy_pcjr_joy
(
    input   logic           clk,            //50Mhz  Anything else and the pulse_div values must be adjusted
    input   logic           reset,
    input   logic           en,             //Active High.  Triggers reading of joystics and generates pulse
    input   logic   [1:0]   clk_select,     //0 - 4.77Mhz   1 - 7.16Mhz   2 - 9.54Mhz   3 - PC/AT 286 3.5MHz
	 input   logic   [4:0]   joy_opts,       //bits: 4 - Adjust timing for Turbo, 3 - Disable P2, 2 - P2 Analog/Digital, 1 - Disable P1, 0 - P1 Analog/Digital
    input   logic   [13:0]  joy0,
    input   logic   [13:0]  joy1,
    input   logic   [15:0]  joya0,
    input   logic   [15:0]  joya1,
    output  logic   [7:0]   d_out           //Format Bit 7 down to 0: P2Btn2, P2Btn1, P1Btn2, P1Btn1, P2-Y_Axis, P2-X_Axis, P1-Y_Axis, P1-X_Axis
);

    logic [7:0] joy0_x_r;                   //Pulse width of X Axis - P1
    logic [7:0] joy1_x_r;                   //Pulse width of X Axis - P2
    logic [7:0] joy0_y_r;                   //Pulse width of Y Axis - P1
    logic [7:0] joy1_y_r;                   //Pulse width of Y Axis - P2
    logic [9:0] joy0_x;                     //Current Joystick input values adjusted for 0-255 range and +/- 15 deadzone
    logic [9:0] joy1_x;
    logic [9:0] joy0_y;
    logic [9:0] joy1_y;
    logic [8:0] counter;                    //Clock cycle counter
    logic [8:0] pulse_div;                  //# of clock cycles in each pulse segment according to cpu freq and clk_select.
                                            // 4.77Mhz ~ 265,  7.16Mhz ~ 200,  9.54Mhz ~ 170 and PC/AT 286 3.5MHz ~ 90.
                                            // These values may need some tweaking to keep joysticks centered.
                                            // The Frogger games has a decent joystick calibration test
                                            
    assign joy0_x = joy_opts[0] ? (joy0[0] ? 8'hFF : joy0[1] ? 8'h00 : 8'h80 ) : 8'd128 + joya0[7:0];
    assign joy1_x = joy_opts[2] ? (joy1[0] ? 8'hFF : joy1[1] ? 8'h00 : 8'h80 ) : 8'd128 + joya1[7:0];
    assign joy0_y = joy_opts[0] ? (joy0[2] ? 8'hFF : joy0[3] ? 8'h00 : 8'h80 ) : 8'd128 + joya0[15:8];
    assign joy1_y = joy_opts[2] ? (joy1[2] ? 8'hFF : joy1[3] ? 8'h00 : 8'h80 ) : 8'd128 + joya1[15:8];


    assign pulse_div = joy_opts[4] ? (clk_select == 1 ? 9'd200 : clk_select == 2 ? 9'd170 : clk_select == 3 ? 9'd90 : 9'd265) : 9'd265;

    always @(posedge clk) begin
        reg en_d;
        en_d <= en;
        if(reset) begin
            counter <= 9'h0;
        end
        else if (en && ~en_d) begin
            joy0_x_r <= joy0_x[7:0] < 8'h70 || joy0_x[7:0] > 8'h90 ? joy0_x[7:0] : 8'h80;
            joy1_x_r <= joy1_x[7:0] < 8'h70 || joy1_x[7:0] > 8'h90 ? joy1_x[7:0] : 8'h80;
            joy0_y_r <= joy0_y[7:0] < 8'h70 || joy0_y[7:0] > 8'h90 ? joy0_y[7:0] : 8'h80;
            joy1_y_r <= joy1_y[7:0] < 8'h70 || joy1_y[7:0] > 8'h90 ? joy1_y[7:0] : 8'h80;
            counter <= 9'h0;
        end
        else if(counter == pulse_div) begin
            if(joy0_x_r != 0) joy0_x_r <= joy0_x_r - 1'b1;
            if(joy1_x_r != 0) joy1_x_r <= joy1_x_r - 1'b1;
            if(joy0_y_r != 0) joy0_y_r <= joy0_y_r - 1'b1;
            if(joy1_y_r != 0) joy1_y_r <= joy1_y_r - 1'b1;
            counter <= 9'h0;
        end
        else counter <= counter + 1'b1;
    end
    
    assign d_out = {~joy1[5],~joy1[4],~joy0[5],~joy0[4],joy_opts[3] || |joy1_y_r, joy_opts[3] || |joy1_x_r, joy_opts[1] || |joy0_y_r, joy_opts[1] || |joy0_x_r};

endmodule
