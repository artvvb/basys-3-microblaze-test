`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/28/2025 05:21:09 PM
// Design Name: 
// Module Name: seven_seg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module seven_seg #(
    parameter integer div_ratio = 32'd100000
) (
    input logic clk,
    input logic reset,
    output logic [7:0] seg,
    output logic [3:0] an
);
    logic [$clog2(div_ratio-1)-1:0] khz_count;
    logic [1:0] digit_count;
    logic [7:0] ten_hz_count;
    logic [15:0] data_count;
    
    logic khz_count_carry;
    logic digit_count_carry;
    logic ten_hz_count_carry;
    
    assign khz_count_carry = (khz_count >= div_ratio-1);
    assign digit_count_carry = (digit_count >= 'd3);
    assign ten_hz_count_carry = (ten_hz_count >= 'd24);
    
    logic [7:0] segments;
    logic [3:0] anode;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            khz_count <= 'b0;
        end else if (khz_count_carry) begin
            khz_count <= 'b0;
        end else begin
            khz_count <= khz_count + 1;
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            digit_count <= 'b0;
        end else if (khz_count_carry) begin
            if (digit_count_carry) begin
                digit_count <= 'b0;
            end else begin
                digit_count <= digit_count + 1;
            end
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            ten_hz_count <= 'b0;
        end else if (khz_count_carry && digit_count_carry) begin
            if (ten_hz_count_carry) begin
                ten_hz_count <= 'b0;
            end else begin
                ten_hz_count <= ten_hz_count + 1;
            end
        end
    end
    always_comb begin
        anode = 4'hf;
        anode[digit_count] = 1'b0;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            data_count <= 'b0;
        end else if (khz_count_carry && digit_count_carry && ten_hz_count_carry) begin
            data_count <= data_count + 1;
        end
    end
    logic [3:0] current_digit;
    always_comb begin
        case (digit_count)
        2'd0: current_digit = data_count[0+:4];
        2'd1: current_digit = data_count[4+:4];
        2'd2: current_digit = data_count[8+:4];
        2'd3: current_digit = data_count[12+:4];
        endcase
    end
    always_comb begin
        case (current_digit)
        4'h0: segments[6:0] = 7'b1000000;
        4'h1: segments[6:0] = 7'b1111001;
        4'h2: segments[6:0] = 7'b0100100;
        4'h3: segments[6:0] = 7'b0110000;
        4'h4: segments[6:0] = 7'b0011001;
        4'h5: segments[6:0] = 7'b0010010;
        4'h6: segments[6:0] = 7'b0000010;
        4'h7: segments[6:0] = 7'b1111000;
        4'h8: segments[6:0] = 7'b0000000;
        4'h9: segments[6:0] = 7'b0010000;
        4'hA: segments[6:0] = 7'b0001000;
        4'hb: segments[6:0] = 7'b0000011;
        4'hC: segments[6:0] = 7'b1000110;
        4'hd: segments[6:0] = 7'b0100001;
        4'hE: segments[6:0] = 7'b0000110;
        4'hF: segments[6:0] = 7'b0001110;
        endcase
    end
    always_comb begin
        segments[7] = (digit_count != 1);
    end
    always_ff @(posedge clk) begin
        an <= anode;
        seg <= segments;
    end
endmodule
