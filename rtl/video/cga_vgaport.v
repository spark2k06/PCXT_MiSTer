// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//

`default_nettype none

module cga_vgaport(

    input wire         clk,
    input wire   [4:0] clkdiv,
    input wire   [3:0] video,
    input wire         composite,
    input wire         hsync,

    // Analog outputs
    output wire  [5:0] red,
    output wire  [5:0] green,
    output wire  [5:0] blue

);

    //Tables for composite color aproximation
    reg [7:0] color_burst [0:63];


    reg signed   [15:0] SINX[0:7];
    reg signed   [15:0] COSX[0:7];

    reg signed   [15:0] Ys[0:7];
    reg signed   [15:0] Is[0:7];
    reg signed   [15:0] Qs[0:7];
    reg signed   [15:0] Y = 0;
    reg signed   [15:0] I = 0;
    reg signed   [15:0] Q = 0;
    reg signed   [15:0] r = 0;
    reg signed   [15:0] g = 0;
    reg signed   [15:0] b = 0;

    reg          [7:0]  luma = 0;
    reg          [7:0]  chroma = 0;

    reg          [17:0] c;
    reg          [1:0]  pix = 0;

    reg          [10:0] pixel_counter = 0;
    reg          [10:0] hcount = 0;
    reg                 composite_aux = 0;

    reg          [3:0]  pixel [0:3];
    reg          [3:0]  composite_video = 0;
    reg          [3:0]  composite_video_aux = 0;    

    initial begin

        // WHITE
        color_burst[0] = 0; color_burst[1] = 0; color_burst[2] = 0; color_burst[3] = 0;
        color_burst[4] = 0; color_burst[5] = 0; color_burst[6] = 0; color_burst[7] = 0;

        // YELLOW
        color_burst[8] = 0; color_burst[9] = 0; color_burst[10] = 0; color_burst[11] = 5; 
        color_burst[12] = 50; color_burst[13] = 50; color_burst[14] = 5; color_burst[15] = 0; 

        // CYAN        
        color_burst[16] = 50; color_burst[17] = 50; color_burst[18] = 0; color_burst[19] = 0;    
        color_burst[20] = 0;    color_burst[21] = 0; color_burst[22] = 50; color_burst[23] = 50;

        // GREEN
        color_burst[24] = 50; color_burst[25] = 0; color_burst[26] = 0; color_burst[27] = 0;
        color_burst[28] = 0;    color_burst[29] = 50; color_burst[30] = 50; color_burst[31] = 50;

        // MAGENTA
        color_burst[32] = 0; color_burst[33] = 50; color_burst[34] = 50; color_burst[35] = 50;
        color_burst[36] = 50; color_burst[37] = 0; color_burst[38] = 0; color_burst[39] = 0;

        // RED
        color_burst[40] = 0;    color_burst[41] = 0;    color_burst[42] = 50; color_burst[43] = 50;
        color_burst[44] = 50; color_burst[45] = 50; color_burst[46] = 0; color_burst[47] = 0;

        // BLUE
        color_burst[48] = 50; color_burst[49] = 50; color_burst[50] = 40; color_burst[51] = 15;
        color_burst[52] = 0;    color_burst[53] = 0; color_burst[54] = 0;    color_burst[55] = 50;

        // BLACK
        color_burst[56] = 50; color_burst[57] = 50; color_burst[58] = 50; color_burst[59] = 50;
        color_burst[60] = 50; color_burst[61] = 50; color_burst[62] = 50; color_burst[63] = 50;

        SINX[0] = -64; SINX[1] = -32; SINX[2] = 12; SINX[3] = 51;
        SINX[4] = 64; SINX[5] = 40; SINX[6] = 0; SINX[7] = -30;    

        COSX[0] = 16; COSX[1] = 53; COSX[2] = 64; COSX[3] = 36;
        COSX[4] = -8; COSX[5] = -50; COSX[6] = -32; COSX[7] = -45;

        pixel[0] = 0; pixel[1] = 0; pixel[2] = 0; pixel[3] = 0;

        Ys[0] = 0; Ys[1] = 0; Ys[2] = 0; Ys[3] = 0; Ys[4] = 0; Ys[5] = 0; Ys[6] = 0; Ys[7] = 0; 
        Is[0] = 0; Is[1] = 0; Is[2] = 0; Is[3] = 0; Is[4] = 0; Is[5] = 0; Is[6] = 0; Is[7] = 0; 
        Qs[0] = 0; Qs[1] = 0; Qs[2] = 0; Qs[3] = 0; Qs[4] = 0; Qs[5] = 0; Qs[6] = 0; Qs[7] = 0;

    end
    
    assign red = c[5:0];
    assign green = c[11:6];
    assign blue = c[17:12];     
 
    always @(negedge clk) begin
 
        pix = {pix[0], clkdiv[1]};

        if (clkdiv[2]) begin
            pixel[1] = (pix == 2'b10) ? video : pixel[1];
            pixel[0] = (pix == 2'b00) ? video : pixel[0];
            composite_video = (pix == 2'b10) ? pixel[1] :
                              (pix == 2'b00) ? pixel[2] : 
                              (pix == 2'b01) ? pixel[2] : 
                              (pix == 2'b11) ? pixel[3] : composite_video;
        end
        else begin
            pixel[3] = (pix == 2'b10) ? video : pixel[3];
            pixel[2] = (pix == 2'b00) ? video : pixel[2];
            composite_video = (pix == 2'b10) ? pixel[3] :
                              (pix == 2'b00) ? pixel[0] : 
                              (pix == 2'b01) ? pixel[0] : 
                              (pix == 2'b11) ? pixel[1] : composite_video;
        end
        
     end

    always @(posedge clk)
    begin

        hcount <= ~hsync ? hcount + 1 : 0;

        if (composite) begin
        
            composite_video_aux = ~(hcount & 1) ? composite_video : composite_video_aux;
            
            //Get luma and chroma
            luma = (composite_video_aux & 8) ? 21 : 0;
            chroma = color_burst[((composite_video_aux & 7) << 3) + (hcount & 7)];

            //Shift arrays << 1
            Ys[0] = Ys[1]; Ys[1] = Ys[2]; Ys[2] = Ys[3]; Ys[3] = Ys[4]; Ys[4] = Ys[5]; Ys[5] = Ys[6]; Ys[6] = Ys[7];
            Is[0] = Is[1]; Is[1] = Is[2]; Is[2] = Is[3]; Is[3] = Is[4]; Is[4] = Is[5]; Is[5] = Is[6]; Is[6] = Is[7];
            Qs[0] = Qs[1]; Qs[1] = Qs[2]; Qs[2] = Qs[3]; Qs[3] = Qs[4]; Qs[4] = Qs[5]; Qs[5] = Qs[6]; Qs[6] = Qs[7];

            //store last pixel data
            Ys[7] = luma + chroma; 
            Is[7] = (luma + chroma) * COSX[hcount & 7];
            Qs[7] = (luma + chroma) * SINX[hcount & 7];            

            //Average (7 pixels)
            Y = (Ys[0] + Ys[1] + Ys[2] + Ys[3] + Ys[4] + Ys[5] + Ys[6] + Ys[7]) >>> 1;
            I = (Is[0] + Is[1] + Is[2] + Is[3] + Is[4] + Is[5] + Is[6] + Is[7]) >>> 2;
            Q = (Qs[0] + Qs[1] + Qs[2] + Qs[3] + Qs[4] + Qs[5] + Qs[6] + Qs[7]) >>> 2;

            //Calculate
            r = Y + (I >>> 5) + (Q >>> 6);
            g = Y - (I >>> 7) - (Q >>> 6);
            b = Y - (I >>> 5) + (Q >>> 4);

            //Clamp
            r = r < 0 ? 0 : (r > 255 ? 255 : r);
            g = g < 0 ? 0 : (g > 255 ? 255 : g);
            b = b < 0 ? 0 : (b > 255 ? 255 : b);            

            c = { b[7:2], g[7:2], r[7:2] };

        end
        else begin
            case(video)
                4'h0: c = 18'b000000_000000_000000;
                4'h1: c = 18'b101010_000000_000000;
                4'h2: c = 18'b000000_101010_000000;
                4'h3: c = 18'b101010_101010_000000;
                4'h4: c = 18'b000000_000000_101010;
                4'h5: c = 18'b101010_000000_101010;
                4'h6: c = 18'b000000_010101_101010; // Brown!
                4'h7: c = 18'b101010_101010_101010;
                4'h8: c = 18'b010101_010101_010101;
                4'h9: c = 18'b111111_010101_010101;
                4'hA: c = 18'b010101_111111_010101;
                4'hB: c = 18'b111111_111111_010101;
                4'hC: c = 18'b010101_010101_111111;
                4'hD: c = 18'b111111_010101_111111;
                4'hE: c = 18'b010101_111111_111111;
                4'hF: c = 18'b111111_111111_111111;
                default: ;
            endcase
        end
    end
endmodule