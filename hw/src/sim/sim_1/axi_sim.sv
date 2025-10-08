`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/04/2025 05:29:39 PM
// Design Name: 
// Module Name: axi_sim
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


module axi_sim;
    logic clk;
    logic reset;
    logic [15:0] sw = 0;
    logic [15:0] led;
    logic [3:0]  vga_r;
    logic [3:0]  vga_g;
    logic [3:0]  vga_b;
    logic        vga_hs;
    logic        vga_vs;

    wire [7:0] ja;
    wire [7:0] jb;
    wire [7:0] jc;
    wire [7:0] jxadc;
//    assign ja[7:4] = ja[3:0];
//    assign jb[7:4] = jb[3:0];
//    assign jc[7:4] = jc[3:0];
//    assign jxadc[7:4] = jxadc[3:0];
    integer mode = 2;
    assign jxadc = {ja[7:0]};
//    assign jxadc = {ja[7:1], 1'b0};
    assign jc = jb;
    wire ps2_clk;
    wire ps2_data;
    
    logic vp_in;
    logic vn_in;
    
    logic [7:0] seg;
    logic [3:0] an;
    
    logic [7:0]  control_awaddr = 0;
    logic        control_awvalid = 0;
    logic        control_awready;
    logic [31:0] control_wdata = 0;
    logic        control_wvalid = 0;
    logic        control_wready;
    logic [1:0]  control_bresp;
    logic        control_bvalid;
    logic        control_bready = 1;
    logic [7:0]  control_araddr = 0;
    logic        control_arvalid = 0;
    logic        control_arready;
    logic [31:0] control_rdata;
    logic        control_rvalid;
    logic        control_rready = 1;
    logic [1:0]  control_rresp;

    top dut (.*);
    
    initial begin
        clk = 0;
        #10 clk = 1;
        forever #5 clk = ~clk;
    end
    
    initial begin
        reset = 0;
        @(posedge clk) reset <= 1;
        @(posedge clk) reset <= 0;
    end
    
    
    task axi_write(input logic [7:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        control_awvalid <= 1;
        control_wvalid <= 1;
        control_awaddr <= addr;
        control_wdata <= data;
        @(posedge clk);
        while (!control_awready && !control_wready)
            @(posedge clk);
        if (control_awready)
            control_awvalid <= 0;
        if (control_wready)
            control_wvalid <= 0;
        while (!control_awready || !control_wready)
            @(posedge clk);
        control_awvalid <= 0;
        control_wvalid <= 0;
        control_bready <= 1;
        @(posedge clk);
        while (!control_bvalid)
            @(posedge clk);
        control_bready <= 0;
    end
    endtask
    
    task axi_read(input logic [7:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        control_arvalid <= 1;
        control_araddr <= addr;
        @(posedge clk);
        while (!control_arready)
            @(posedge clk);
        control_arvalid <= 0;
        control_rready <= 1;
        @(posedge clk);
        while (!control_rvalid)
            @(posedge clk);
        control_rready <= 0;
        data = control_rdata;
    end
    endtask
    
    logic [31:0] rdata;
    logic flag; /* Flag end of each test for simple nav in sim */
    logic pass;
    
    initial begin
        flag = 0;
        #100;
        axi_write(dut.XADC_SET_CHAN_ADDR, 32'h0);
        axi_read(dut.STATUS_ADDR, rdata);
        while ((rdata & 32'h2) == 0)
            axi_read(dut.STATUS_ADDR, rdata);
        axi_read(dut.XADC_DATA_ADDR, rdata);
        flag <= 1;
        pass <= 1; // no test condition, monitoring
        @(posedge clk) flag <= 0;
        pass <= 'bz;
        
        #100;
        axi_write(dut.DIO_SETTINGS_ADDR, {14'b0, mode[1:0], 8'd24, 8'd49}); // {_, mode[1:0], output_phase[7:0], output_divider[7:0]}
        #100000;
        axi_read(dut.DIO_STATUS_ADDR, rdata); // 0x10 is good. no errors, running.
        flag <= 1;
        pass <= (~|rdata[3:0]);
        @(posedge clk) flag <= 0;
        pass <= 'bz;
        axi_write(dut.DIO_SETTINGS_ADDR, {14'b0, 2'b00, 8'd3, 8'd7}); // {_, mode[1:0], output_phase[7:0], output_divider[7:0]}
        
        
        #100;
        axi_read(dut.PS2_POS_ADDR, rdata);
        flag <= 1;
        pass <= 'b1; // no test condition
        @(posedge clk) flag <= 0;
        pass <= 'bz;
        
        #100;
        axi_write(dut.BRAM_SEED_ADDR, 32'hdeadbeef);
        axi_read(dut.BRAM_STATUS_ADDR, rdata);
        while (!rdata[1])
            axi_read(dut.BRAM_STATUS_ADDR, rdata);
        // pass test if rdata[0] == 1 // look for 2'b11 on rdata
        flag <= 1;
        pass <= 1;
        @(posedge clk) flag <= 0;
        pass <= 'bz;
    end
    always_ff @(posedge clk) assert (!flag || pass) else $warning("Something failed!");
endmodule
