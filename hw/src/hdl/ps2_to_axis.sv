`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/23/2025 12:35:54 PM
// Design Name: 
// Module Name: ps2_to_axis
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


module ps2_to_axis (
    input logic clk,
    input logic reset,
    
    input logic        pxl_clk,
    input logic [11:0] mouse_x_pos,
    input logic [11:0] mouse_y_pos,
    input logic        new_event,
    
    output logic [31:0] ps2_pos_tdata, // 24 down to 8 width conversion, {mouse_x_pos, mouse_y_pos} 
    output logic        ps2_pos_tvalid,
    input  logic        ps2_pos_tready
);
    logic [23:0] pxl_tdata;
    logic        pxl_tvalid;
    logic        pxl_tready;
    
    logic [23:0] sys_tdata;
    logic        sys_tvalid;
    logic        sys_tready;
    
    always_ff @(posedge pxl_clk) begin
        if (reset) begin
            pxl_tdata <= 'b0;
            pxl_tvalid <= 'b0;
        end else if (new_event) begin
            pxl_tdata <= {mouse_x_pos, mouse_y_pos};
            pxl_tvalid <= 1'b1;
        end else if (pxl_tready) begin
            pxl_tvalid <= 'b0;
        end
    end
    
    axis_clock_converter_0 your_instance_name (
        .s_axis_aresetn (!reset),       // input wire s_axis_aresetn
        .m_axis_aresetn (!reset),       // input wire m_axis_aresetn
        .s_axis_aclk    (pxl_clk),      // input wire s_axis_aclk
        .s_axis_tvalid  (pxl_tvalid),   // input wire s_axis_tvalid
        .s_axis_tready  (pxl_tready),   // output wire s_axis_tready
        .s_axis_tdata   (pxl_tdata),    // input wire [23 : 0] s_axis_tdata
        .m_axis_aclk    (clk),          // input wire m_axis_aclk
        .m_axis_tvalid  (sys_tvalid),   // output wire m_axis_tvalid
        .m_axis_tready  (sys_tready),   // input wire m_axis_tready
        .m_axis_tdata   (sys_tdata)     // output wire [23 : 0] m_axis_tdata
    );
    
    always_comb sys_tready = 1;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            ps2_pos_tdata <= 'b0;
            ps2_pos_tvalid <= 0;
        end else if (sys_tvalid) begin
            ps2_pos_tdata <= sys_tdata;
            ps2_pos_tvalid <= 1;
        end else if (ps2_pos_tready) begin
            ps2_pos_tvalid <= 0;
        end
    end
endmodule
