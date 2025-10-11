`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/10/2025 02:29:39 PM
// Design Name: 
// Module Name: status_leds
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

module status_leds #(
    parameter HANDLE_CLEAR_INTERNALLY = 1,
    parameter integer CLEAR_PERIOD = 10_000_000 - 1
) (
    input logic         clk,
    input logic         reset,
    input logic  [15:0] status, // status 1 indicates BAD on that particular line
    input logic         clear,
    output logic [15:0] led
);
    /*
    general goal: extend pulses on any status pin out to a half second or greater
    the clear line will be toggled high whenever the controller loops
    whenever a status bit toggles high, set that bit in the output register. 
    whenever clear toggles high, "capture" that bit, marking it to be allowed to be cleared on the next clear pass.
    */
    logic clear_int;
    generate
        if (HANDLE_CLEAR_INTERNALLY) begin
            logic [$clog2(CLEAR_PERIOD)-1:0] counter;
            
            always_comb clear_int = (counter >= CLEAR_PERIOD);

            always_ff @(posedge clk) begin
                if (reset) begin
                    counter <= 'b0;
                end else if (clear_int) begin
                    counter <= 'b0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end else begin
            always_comb clear_int = clear;
        end
    endgenerate
    logic [15:0] register;
    logic [15:0] captured;
    
    always_comb led = register;

    always_ff @(posedge clk) begin
        integer i;
        if (reset) begin
            register <= 'b0;
            captured <= 'b0;
        end else begin
            for (i = 0; i < 16; i = i + 1) begin
                if (status[i]) begin
                    register[i] <= 1;
                    captured[i] <= 0;
                end if (register[i] && clear_int) begin
                    if (!captured[i]) begin
                        captured[i] <= 1;
                        // leave register high
                    end else begin
                        captured[i] <= 0;
                        register[i] <= 0;
                    end
                end
            end
        end
    end
endmodule