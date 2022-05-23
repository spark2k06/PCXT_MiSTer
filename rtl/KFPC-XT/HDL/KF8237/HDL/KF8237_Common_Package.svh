//
// KF8237_Common_Package
//
// Written by Kitune-san
//
`ifndef KF8237_COMMON_PACKAGE_SVH
`define KF8237_COMMON_PACKAGE_SVH

package KF8237_Common_Package;
    function logic [3:0] rotate_right (input [3:0] source, input [1:0] rotate);
        casez (rotate)
            2'b00:   rotate_right = { source[0],   source[3:1] };
            2'b01:   rotate_right = { source[1:0], source[3:2] };
            2'b10:   rotate_right = { source[2:0], source[3]   };
            2'b11:   rotate_right = source;
            default: rotate_right = source;
        endcase
    endfunction

    function logic [3:0] rotate_left (input [3:0] source, input [1:0] rotate);
        casez (rotate)
            2'b00:   rotate_left = { source[2:0], source[3]   };
            2'b01:   rotate_left = { source[1:0], source[3:2] };
            2'b10:   rotate_left = { source[0],   source[3:1] };
            2'b11:   rotate_left = source;
            default: rotate_left = source;
        endcase
    endfunction

    function logic [3:0] resolv_priority (input [3:0] request);
        if      (request[0] == 1'b1)    resolv_priority = 4'b0001;
        else if (request[1] == 1'b1)    resolv_priority = 4'b0010;
        else if (request[2] == 1'b1)    resolv_priority = 4'b0100;
        else if (request[3] == 1'b1)    resolv_priority = 4'b1000;
        else                            resolv_priority = 4'b0000;
    endfunction

    function logic [3:0] num2bit (input [1:0] source);
        casez (source)
            2'b00:   num2bit = 8'b00000001;
            2'b01:   num2bit = 8'b00000010;
            2'b10:   num2bit = 8'b00000100;
            2'b11:   num2bit = 8'b00001000;
            default: num2bit = 8'b00000000;
        endcase
    endfunction

    function logic [1:0] bit2num (input [3:0] source);
        if      (source[0] == 1'b1) bit2num = 2'b00;
        else if (source[1] == 1'b1) bit2num = 2'b01;
        else if (source[2] == 1'b1) bit2num = 2'b10;
        else if (source[3] == 1'b1) bit2num = 2'b11;
        else                        bit2num = 2'b00;
    endfunction

endpackage

`endif
