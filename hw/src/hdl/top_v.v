`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/03/2025 04:57:08 PM
// Design Name: 
// Module Name: top_v
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


module top_v(
    input  wire        control_aclk,
    input  wire        control_aresetn,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    (* IOB = "TRUE" *) inout wire [7:0] ja,
    (* IOB = "TRUE" *) inout wire [7:0] jb,
    (* IOB = "TRUE" *) inout wire [7:0] jc,
    (* IOB = "TRUE" *) inout wire [7:0] jxadc,
    inout  wire ps2_clk,
    inout  wire ps2_data,
//    input  wire vp_in, // fixed pin - no LOC required
//    input  wire vn_in, // fixed pin - no LOC required
    output wire [7:0] seg,
    output wire [3:0] an,
    input  wire [7:0]  control_awaddr,
    input  wire        control_awvalid,
    output wire        control_awready,
    input  wire [31:0] control_wdata,
    input  wire        control_wvalid,
    output wire        control_wready,
    output wire [1:0]  control_bresp,
    output wire        control_bvalid,
    input  wire        control_bready,
    input  wire [7:0]  control_araddr,
    input  wire        control_arvalid,
    output wire        control_arready,
    output wire [31:0] control_rdata,
    output wire        control_rvalid,
    input  wire        control_rready,
    output wire [1:0]  control_rresp
);
    top top_inst (
        .clk        (control_aclk),
        .reset      (!control_aresetn),
        .sw         (sw),
        .led        (led),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .vga_hs     (vga_hs),
        .vga_vs     (vga_vs),
        .ja         (ja),
        .jb         (jb),
        .jc         (jc),
        .jxadc      (jxadc),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
//        .vp_in      (vp_in), // fixed pin - no LOC required
//        .vn_in      (vn_in), // fixed pin - no LOC required
        .seg        (seg),
        .an         (an),
        .control_awaddr  (control_awaddr),
        .control_awvalid (control_awvalid),
        .control_awready (control_awready),
        .control_wdata   (control_wdata),
        .control_wvalid  (control_wvalid),
        .control_wready  (control_wready),
        .control_bresp   (control_bresp),
        .control_bvalid  (control_bvalid),
        .control_bready  (control_bready),
        .control_araddr  (control_araddr),
        .control_arvalid (control_arvalid),
        .control_arready (control_arready),
        .control_rdata   (control_rdata),
        .control_rvalid  (control_rvalid),
        .control_rready  (control_rready),
        .control_rresp   (control_rresp)
    );
endmodule
