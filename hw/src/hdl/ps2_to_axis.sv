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
    input logic        pxl_clk_aresetn,
    
    input logic [11:0] mouse_x_pos,
    input logic [11:0] mouse_y_pos,
    input logic        mouse_err,
    input logic        new_event,
    
    output logic [31:0] ps2_pos_tdata,
    // {    new_data,       // indicate whether this particular sample has been read before or if there's a change
    //      not_connected,  // until any mouse event has been captured, indicate lack of mouse presence. may take some startup time to clear
    //      mouse_error,    // indicates read_id failure in communication with the mouse, indicating a potential disconnect
    //      mouse_x_pos,    // current mouse X coordinate
    //      mouse_y_pos     // current mouse Y coordinate
    // } 
    output logic        ps2_pos_tvalid,
    input  logic        ps2_pos_tready
);
    logic [31:0] pxl_tdata;
    logic        pxl_tvalid;
    logic        pxl_tready;
    
    logic [31:0] sys_tdata;
    logic        sys_tvalid;
    logic        sys_tready;
    
    always_ff @(posedge pxl_clk) begin
        if (!pxl_clk_aresetn) begin
            pxl_tdata <= 'b0;
            pxl_tvalid <= 'b0;
        end else if (new_event) begin
            pxl_tdata <= {mouse_err, mouse_x_pos, mouse_y_pos};
            pxl_tvalid <= 1'b1;
        end else if (pxl_tready) begin
            pxl_tvalid <= 'b0;
        end
    end
    
    axis_clock_converter_0 your_instance_name (
        .s_axis_aresetn (pxl_clk_aresetn), // input wire s_axis_aresetn
        .m_axis_aresetn (!reset),         // input wire m_axis_aresetn
        .s_axis_aclk    (pxl_clk),        // input wire s_axis_aclk
        .s_axis_tvalid  (pxl_tvalid),     // input wire s_axis_tvalid
        .s_axis_tready  (pxl_tready),     // output wire s_axis_tready
        .s_axis_tdata   (pxl_tdata),      // input wire [31 : 0] s_axis_tdata
        .m_axis_aclk    (clk),            // input wire m_axis_aclk
        .m_axis_tvalid  (sys_tvalid),     // output wire m_axis_tvalid
        .m_axis_tready  (sys_tready),     // input wire m_axis_tready
        .m_axis_tdata   (sys_tdata)       // output wire [31 : 0] m_axis_tdata
    );
    
    always_comb sys_tready = 1;
    
    logic initializing = 1; // indicates whether any valid sample has been received, showing that there is a mouse present to bring the PS/2 controller out of reset
    logic new_data = 1;
    always_ff @(posedge clk) begin
        if (reset) begin
            initializing <= 1;
        end else if (sys_tvalid) begin
            initializing <= 0;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            new_data <= 1;
        end else if (sys_tvalid) begin
            new_data <= 1;
        end else if (ps2_pos_tready) begin
            new_data <= 0;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            ps2_pos_tdata[24:0] <= 'b0;
        end else if (sys_tvalid) begin
            ps2_pos_tdata[24:0] <= sys_tdata;
        end
    end
    
    always_comb ps2_pos_tvalid = 1;
    always_comb ps2_pos_tdata[31:25] = {5'b0, new_data, initializing};
endmodule
