`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/29/2025 05:17:56 PM
// Design Name: 
// Module Name: bram_test
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


module bram_test #(
    parameter logic [15:0] ADDR_MAX = 16'h3ff
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        seed_tvalid,
    output logic        seed_tready,
    input  logic [31:0] seed_tdata,
    output logic [31:0] status_tdata, // "0" + {reset busy, done, test passed}
    output logic        status_tvalid,
    input  logic        status_tready
);

    logic [31:0] seed;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic reset_busy;
    logic [15:0] addr;
    logic wen, en;
    
    localparam logic [15:0] ADDR_READ_VALID = 16'd2;
    
    enum integer {
        RESET_BUSY,
        WAIT_FOR_SEED,
        WRITE,
        SWITCHOVER, // 2 clock cycle read latency
        READ,
        FLUSH, // 2 clock cycle read latency
        WAIT_FOR_STATUS
    } state;
    
    always_comb seed_tready = WAIT_FOR_SEED;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= RESET_BUSY;
        end else case (state)
        RESET_BUSY:         if (!reset_busy)                    state <= WAIT_FOR_SEED;
        WAIT_FOR_SEED:      if (seed_tvalid)                    state <= WRITE;
        WRITE:              if (addr == ADDR_MAX)               state <= SWITCHOVER;
        SWITCHOVER:         if (addr + 1 == ADDR_READ_VALID)    state <= READ;
        READ:               if (addr == ADDR_MAX)               state <= FLUSH;
        FLUSH:              if (addr + 1 == ADDR_READ_VALID)    state <= WAIT_FOR_STATUS;
        WAIT_FOR_STATUS:    if (status_tready)                  state <= WAIT_FOR_SEED;
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            addr <= 'b0;
        end else if (state == WAIT_FOR_SEED || state == WAIT_FOR_STATUS) begin
            addr <= 'b0;
        end else if (addr == ADDR_MAX) begin
            addr <= 'b0;
        end else begin
            addr <= addr + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            seed <= 0;
        end else if (state == WAIT_FOR_SEED) begin
            if (seed_tvalid) begin
                seed <= seed_tdata;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            wdata <= 0;
        end else if (state == WAIT_FOR_SEED) begin
            wdata <= seed_tdata; 
        end else if (state == WRITE && addr == ADDR_MAX) begin
            wdata <= seed;
        end else if (state == WRITE || state == READ) begin
            wdata <= {wdata[30:0], wdata[31] ^ wdata[21] ^ wdata[1] ^ wdata[0]};
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            status_tdata[0] <= 1;
        end else if (state == READ && addr >= ADDR_READ_VALID && wdata != rdata) begin
            status_tdata[0] <= 0;
        end else if (state == WAIT_FOR_SEED) begin
            status_tdata[0] <= 1;
        end
    end
    always_comb status_tdata[1] = (state == WAIT_FOR_STATUS);
    always_comb status_tdata[31:2] = 'b0;
    always_comb status_tvalid = 1;
    
    always_comb wen = (state == WRITE);
    always_comb en = (state == WRITE || state == SWITCHOVER || state == READ);    
    
    blk_mem_gen_0 bram_inst (
        .clka       (clk),          // input wire clka
        .rsta       (reset),        // input wire rsta
        .ena        (en),           // input wire ena
        .wea        (wen),          // input wire [0 : 0] wea
        .addra      (addr),         // input wire [15 : 0] addra
        .dina       (wdata),        // input wire [31 : 0] dina
        .douta      (rdata),        // output wire [31 : 0] douta
        .rsta_busy  (reset_busy)    // output wire rsta_busy
    );
endmodule
