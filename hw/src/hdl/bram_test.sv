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
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        seed_tvalid,
    output logic        seed_tready,
    input  logic [31:0] seed_tdata,
    input  logic        addr_max_tvalid,
    input  logic [31:0] addr_max_tdata, // {en_bank_1, }
    output logic        addr_max_tready,
    output logic [31:0] status_tdata, // "0" + {reset busy, done, test passed}
    output logic        status_tvalid,
    input  logic        status_tready,
    output logic        error
);
    localparam integer ADDR_WIDTH = 13;
    localparam logic [31:0] ADDR_MAX = 'h1fff; // {number of times to loop over the address space, address max}

    logic [31:0] seed;
    logic [31:0] wdata;
    logic [31:0] rdata_0;
    logic [31:0] rdata_1;
    logic reset_busy_0;
    logic reset_busy_1;
    logic [ADDR_WIDTH-1:0] addr;
    logic wen, en;
    
    localparam logic [ADDR_WIDTH-1:0] ADDR_READ_VALID = 'd2; // switchover period
    logic [31:0] addr_max_reg;
    logic [ADDR_WIDTH-1:0] addr_max;
    logic [31-ADDR_WIDTH-1:0] loops;
    logic [31-ADDR_WIDTH-1:0] loops_reg;
    logic en_bank_1;
    always_comb {en_bank_1, loops, addr_max} = addr_max_reg;
    
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
    always_comb addr_max_tready = WAIT_FOR_SEED;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            addr_max_reg <= ADDR_MAX;
        end else if (addr_max_tvalid && addr_max_tready) begin
            addr_max_reg <= addr_max_tdata;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= RESET_BUSY;
        end else case (state)
        RESET_BUSY:         if (!reset_busy_0 && !reset_busy_1) state <= WAIT_FOR_SEED;
        WAIT_FOR_SEED:      if (seed_tvalid)                    state <= WRITE;
        WRITE:              if (addr == addr_max)               state <= SWITCHOVER;
        SWITCHOVER:         if (addr + 1 == ADDR_READ_VALID)    state <= READ;
        READ:               if (addr == addr_max)               state <= FLUSH;
        FLUSH:              if (addr + 1 == ADDR_READ_VALID) begin
                                if (loops_reg == 0)
                                    state <= WAIT_FOR_STATUS;
                                else
                                    state <= WRITE;
                            end
        WAIT_FOR_STATUS:    if (status_tready) state <= WAIT_FOR_SEED;
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            loops_reg <= 0;
        end else if (addr_max_tvalid && addr_max_tready) begin
            loops_reg <= loops;
        end else if (state == FLUSH && addr + 1 == ADDR_READ_VALID && loops_reg > 0) begin
            loops_reg <= loops_reg - 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            addr <= 'b0;
        end else if (state == WAIT_FOR_SEED || state == WAIT_FOR_STATUS) begin
            addr <= 'b0;
        end else if (addr == addr_max) begin
            addr <= 'b0;
        end else if (addr + 1 == ADDR_READ_VALID && state == FLUSH) begin
            addr <= 'b0;
        end else begin
            addr <= addr + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            seed <= 0;
        end else if (seed_tready && seed_tvalid) begin
            seed <= seed_tdata;
        end
    end
    
    logic [31:0] rdata_compare;
    always_ff @(posedge clk) begin
        if (reset) begin
            rdata_compare <= 0;
        end else if (state == WAIT_FOR_SEED && seed_tvalid) begin
            rdata_compare <= seed_tdata;
        end else if (state == READ) begin
            rdata_compare <= {rdata_compare[30:0], rdata_compare[31] ^ rdata_compare[21] ^ rdata_compare[1] ^ rdata_compare[0]};
//            rdata_compare <= rdata_compare + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            wdata <= 0;
        end else if (state == WAIT_FOR_SEED && seed_tvalid) begin
            wdata <= seed_tdata; 
        end else if (state == WRITE) begin
            wdata <= {wdata[30:0], wdata[31] ^ wdata[21] ^ wdata[1] ^ wdata[0]};
//            wdata <= wdata + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            status_tdata[0] <= 1;
            error <= 0;
        end else if (state == READ && addr >= ADDR_READ_VALID) begin
            if (rdata_compare != rdata_0 || (rdata_compare != rdata_1 && en_bank_1)) begin
                status_tdata[0] <= 0;
                error <= 1;
            end
        end else if (state == WAIT_FOR_SEED) begin
            status_tdata[0] <= 1;
            error <= 0;
        end
    end
    always_comb status_tdata[1] = (state == WAIT_FOR_STATUS);
    always_comb status_tdata[31:2] = 'b0;
    always_comb status_tvalid = 1;
    
    always_comb wen = (state == WRITE);
    always_comb en = (state == WRITE || state == SWITCHOVER || state == READ);    
    
    blk_mem_gen_0 bram_bank_0_inst (
        .clka       (clk),          // input wire clka
        .rsta       (reset),        // input wire rsta
        .ena        (en),           // input wire ena
        .wea        (wen),          // input wire [0 : 0] wea
        .addra      (addr),         // input wire [ADDR_WIDTH-1 : 0] addra
        .dina       (wdata),        // input wire [31 : 0] dina
        .douta      (rdata_0),      // output wire [31 : 0] douta
        .rsta_busy  (reset_busy_0)    // output wire rsta_busy
    );
    blk_mem_gen_0 bram_bank_1_inst (
        .clka       (clk),          // input wire clka
        .rsta       (reset),        // input wire rsta
        .ena        (en && en_bank_1),  // input wire ena
        .wea        (wen && en_bank_1), // input wire [0 : 0] wea
        .addra      (addr),         // input wire [ADDR_WIDTH-1 : 0] addra
        .dina       (wdata),        // input wire [31 : 0] dina
        .douta      (rdata_1),      // output wire [31 : 0] douta
        .rsta_busy  (reset_busy_1)  // output wire rsta_busy
    );
endmodule
