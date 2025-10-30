`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/27/2025 06:07:33 PM
// Design Name: 
// Module Name: top
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


module top (
    input  logic        clk,
    input  logic        reset,
    input  logic        pxl_clk,
    input  logic        pxl_clk_aresetn,
    
    input  logic [15:0] sw,
    output logic [15:0] led,
    
    input logic flash_error,
    input logic uart_error,
    
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,
    output logic        vga_hs,
    output logic        vga_vs,

    (* IOB = "TRUE" *) inout wire [7:0] ja,
    (* IOB = "TRUE" *) inout wire [7:0] jb,
    (* IOB = "TRUE" *) inout wire [7:0] jc,
    (* IOB = "TRUE" *) inout wire [7:0] jxadc,
    
    inout wire ps2_clk,
    inout wire ps2_data,
    
//    input logic vp_in, // fixed pin - no LOC required
//    input logic vn_in, // fixed pin - no LOC required
    
    output logic [7:0] seg,
    output logic [3:0] an,
    
    input  logic [7:0]  control_awaddr,
    input  logic        control_awvalid,
    output logic        control_awready,
    input  logic [31:0] control_wdata,
    input  logic        control_wvalid,
    output logic        control_wready,
    output logic [1:0]  control_bresp,
    output logic        control_bvalid,
    input  logic        control_bready,
    input  logic [7:0]  control_araddr,
    input  logic        control_arvalid,
    output logic        control_arready,
    output logic [31:0] control_rdata,
    output logic        control_rvalid,
    input  logic        control_rready,
    output logic [1:0]  control_rresp
);
    logic [31:0] wdata_reg;
    logic [7:0] awaddr_reg;
    logic [7:0] araddr_reg;
    logic mouse_err_2;
    
    enum integer {
        INTF_AWREADY_AND_WREADY,
        INTF_AWREADY,
        INTF_WREADY,
        INTF_BVALID_STROBE,
        INTF_BVALID
    } w_state;
    
    enum integer {
        INTF_ARREADY,
        INTF_RVALID
    } r_state;
    
    logic write_strobe; // One clock cycle pulse when both address and data have been captured
    logic read_strobe; // One clock cycle pulse for end of read transaction
    
    always_ff @(posedge clk) begin
        if (reset) begin
            w_state <= INTF_AWREADY_AND_WREADY;
        end else case (w_state)
        INTF_AWREADY_AND_WREADY: begin
            case ({control_awvalid, control_wvalid})
                2'b11: w_state <= INTF_BVALID_STROBE;
                2'b01: w_state <= INTF_AWREADY;
                2'b10: w_state <= INTF_WREADY;
                2'b00: w_state <= INTF_AWREADY_AND_WREADY;
            endcase
        end
        INTF_AWREADY:       if (control_awvalid) w_state <= INTF_BVALID_STROBE;
        INTF_WREADY:        if (control_wvalid) w_state <= INTF_BVALID_STROBE;
        INTF_BVALID_STROBE: begin
            if (control_bready)
                w_state <= INTF_AWREADY_AND_WREADY;
            else
                w_state <= INTF_BVALID;
        end
        INTF_BVALID:        if (control_bready) w_state <= INTF_AWREADY_AND_WREADY;
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            wdata_reg <= 'b0;
        end else if (w_state == INTF_WREADY || w_state == INTF_AWREADY_AND_WREADY) begin
            if (control_wvalid) begin
                wdata_reg <= control_wdata;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            awaddr_reg <= 'b0;
        end else if (w_state == INTF_AWREADY || w_state == INTF_AWREADY_AND_WREADY) begin
            if (control_awvalid) begin
                awaddr_reg <= control_awaddr;
            end
        end
    end
    
    always_comb write_strobe = (w_state == INTF_BVALID_STROBE);
    always_comb control_bvalid = (w_state == INTF_BVALID_STROBE || w_state == INTF_BVALID);
    always_comb control_awready = (w_state == INTF_AWREADY_AND_WREADY || w_state == INTF_AWREADY);
    always_comb control_wready = (w_state == INTF_AWREADY_AND_WREADY || w_state == INTF_WREADY);
    always_comb control_bresp = 2'b00; /* OKAY */
    
    always_ff @(posedge clk) begin
        if (reset) begin
            r_state <= INTF_ARREADY;
        end else case (r_state)
            INTF_ARREADY:   if (control_arvalid)  r_state <= INTF_RVALID;
            INTF_RVALID:    if (control_rready)   r_state <= INTF_ARREADY;
        endcase
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            araddr_reg <= 'b0;
        end else if (r_state == INTF_ARREADY) begin
            if (control_arvalid) begin
                araddr_reg <= control_araddr;
            end
        end
    end
    
    always_comb read_strobe = (r_state == INTF_RVALID) && control_rready;
    always_comb control_rvalid = (r_state == INTF_RVALID);
    always_comb control_arready = (r_state == INTF_ARREADY);
    always_comb control_rresp = 2'b00; /* OKAY */
    
    /* Interface definitions */
    localparam [7:0] STATUS_ADDR = 0;             // READ-ONLY
    localparam [7:0] XADC_SET_CHAN_ADDR = 4;      // WRITE-ONLY
    localparam [7:0] XADC_DATA_ADDR = 8;          // CLEAR-ON-READ
    localparam [7:0] DIO_SETTINGS_ADDR = 12;      // WRITE-ONLY
    localparam [7:0] DIO_STATUS_ADDR = 16;        // CLEAR-ON-READ
    localparam [7:0] PS2_POS_ADDR = 20;           // READ-ONLY
    localparam [7:0] BRAM_SEED_ADDR = 24;         // WRITE-ONLY
    localparam [7:0] BRAM_ADDR_MAX_ADDR = 28;     // WRITE-ONLY
    localparam [7:0] BRAM_STATUS_ADDR = 32;       // READ-ONLY
    localparam [7:0] DIO_COUNTER_MAX_ADDR = 36;   // WRITE-ONLY
    localparam [7:0] DIO_OUTPUT_PHASE_ADDR = 40;  // WRITE-ONLY
    
    logic [7:0] xadc_set_addr_tdata;
    logic       xadc_set_addr_tvalid;
    logic       xadc_set_addr_tready;
    logic [31:0] xadc_tdata;
    logic        xadc_tvalid;
    logic        xadc_tready;
    logic [31:0] dio_settings_tdata; /* {set_mode[0], output_phase[7:0], counter_period[7:0]} */
    logic        dio_settings_tvalid;
    logic        dio_settings_tready;
    logic [31:0] dio_status_tdata;
    logic        dio_status_tvalid;
    logic        dio_status_tready;
    logic [31:0] ps2_pos_tdata;
    logic        ps2_pos_tvalid;
    logic        ps2_pos_tready;
    logic [31:0] bram_seed_tdata;
    logic        bram_seed_tvalid;
    logic        bram_seed_tready;
    logic [31:0] bram_addr_max_tdata;
    logic        bram_addr_max_tvalid;
    logic        bram_addr_max_tready;
    logic [31:0] bram_status_tdata;
    logic        bram_status_tvalid;
    logic        bram_status_tready;
    logic [31:0] dio_counter_max_tdata;
    logic        dio_counter_max_tvalid;
    logic        dio_counter_max_tready;
    logic [31:0] dio_output_phase_tdata;
    logic        dio_output_phase_tvalid;
    logic        dio_output_phase_tready;

    always_comb begin
        case (araddr_reg)
        STATUS_ADDR: control_rdata = {
            23'b0,
            dio_counter_max_tready,
            dio_output_phase_tready,
            bram_status_tvalid,
            bram_seed_tready, // also gives the status of bram_addr_max_tready
            ps2_pos_tvalid,
            dio_status_tvalid,
            dio_settings_tready,
            xadc_tvalid,
            xadc_set_addr_tready
        };
        XADC_DATA_ADDR:     control_rdata = xadc_tdata;
        DIO_STATUS_ADDR:    control_rdata = dio_status_tdata; // CLEAR-ON-READ
        PS2_POS_ADDR:       control_rdata = ps2_pos_tdata; // READ-ONLY
        BRAM_STATUS_ADDR:   control_rdata = bram_status_tdata; // READ-ONLY
        default:            control_rdata = 'b0;
        endcase
    end
    
//    always_comb xadc_set_addr_tdata = wdata_reg;
    always_comb dio_settings_tdata     = wdata_reg;
    always_comb bram_seed_tdata        = wdata_reg;
    always_comb bram_addr_max_tdata    = wdata_reg;
    always_comb dio_output_phase_tdata = wdata_reg;
    always_comb dio_counter_max_tdata  = wdata_reg;
    
//    always_comb xadc_set_addr_tvalid    = write_strobe && (awaddr_reg == XADC_SET_CHAN_ADDR);
    always_comb dio_settings_tvalid     = write_strobe && (awaddr_reg == DIO_SETTINGS_ADDR);
    always_comb bram_seed_tvalid        = write_strobe && (awaddr_reg == BRAM_SEED_ADDR);
    always_comb bram_addr_max_tvalid    = write_strobe && (awaddr_reg == BRAM_ADDR_MAX_ADDR);
    always_comb dio_output_phase_tvalid = write_strobe && (awaddr_reg == DIO_OUTPUT_PHASE_ADDR);
    always_comb dio_counter_max_tvalid  = write_strobe && (awaddr_reg == DIO_COUNTER_MAX_ADDR);
    
//    always_comb xadc_tready         = read_strobe && (araddr_reg == XADC_DATA_ADDR);
    always_comb dio_status_tready   = read_strobe && (araddr_reg == DIO_STATUS_ADDR);
    always_comb ps2_pos_tready      = read_strobe && (araddr_reg == PS2_POS_ADDR);
    always_comb bram_status_tready  = read_strobe && (araddr_reg == BRAM_STATUS_ADDR);
    
    /* Implement Test Hardware */
    
//    xadc xadc_inst (
//        .clk             (clk),
//        .reset           (reset),
//        .vp_in           (vp_in),
//        .vn_in           (vn_in),
//        .set_addr_tvalid (xadc_set_addr_tvalid),
//        .set_addr_tdata  (xadc_set_addr_tdata),
//        .set_addr_tready (xadc_set_addr_tready),
//        .xadc_tdata      (xadc_tdata),
//        .xadc_tvalid     (xadc_tvalid),
//        .xadc_tready     (xadc_tready)
//    );
    always_comb xadc_tvalid = 1;
    always_comb xadc_set_addr_tready = 1;
    
    logic [3:0] dio_error;
    dio_test dio_inst (
        .clk                             (clk),
        .reset                           (reset),
        .ja                              (ja),
        .jb                              (jb),
        .jc                              (jc),
        .jxadc                           (jxadc),
        .dio_counter_max_tdata           (dio_counter_max_tdata),
        .dio_counter_max_tvalid          (dio_counter_max_tvalid),
        .dio_counter_max_tready          (dio_counter_max_tready),
        .dio_output_phase_tdata          (dio_output_phase_tdata),
        .dio_output_phase_tvalid         (dio_output_phase_tvalid),
        .dio_output_phase_tready         (dio_output_phase_tready),
        .dio_settings_tdata              (dio_settings_tdata),
        .dio_settings_tvalid             (dio_settings_tvalid),
        .dio_settings_tready             (dio_settings_tready),
        .dio_counter_status_tvalid       (dio_status_tvalid),
        .dio_counter_status_tdata        (dio_status_tdata),
        .dio_counter_status_tready       (dio_status_tready),
        .dio_error                       (dio_error)
    );
    
    logic [11:0] mouse_x_pos;
    logic [11:0] mouse_y_pos;
    logic mouse_err;
    logic new_event;
    
    vga_ctrl vga_inst (
        .CLK_I              (pxl_clk),
        .VGA_HS_O           (vga_hs),
        .VGA_VS_O           (vga_vs),
        .VGA_RED_O          (vga_r),
        .VGA_GREEN_O        (vga_g),
        .VGA_BLUE_O         (vga_b),
        .PS2_CLK            (ps2_clk),
        .PS2_DATA           (ps2_data),
        .MOUSE_X_POS_O      (mouse_x_pos),
        .MOUSE_Y_POS_O      (mouse_y_pos),
        .MOUSE_ERR_O        (mouse_err),
        .NEW_EVENT_O        (new_event),
        .ERR_CTL_IN_RESET   (mouse_err_2),
        .state_dbg          ()
    );
    
    
    logic [14:0] status_leds;
    logic mouse_disconnect;
    logic bram_error;
    
    always_comb status_leds = {dio_error, 7'b0, uart_error, mouse_disconnect, flash_error, bram_error};
    
    status_leds #(
        .HANDLE_CLEAR_INTERNALLY (1),
        .CLEAR_PERIOD            (32'd50_000_000 - 1)
    ) led_inst (
        .clk     (clk),
        .reset   (reset),
        .status  (status_leds),
        .clear   (),
        .led     (led)
    );
    
    ps2_to_axis ps2_to_axis_inst (
        .clk                    (clk),
        .reset                  (reset),
        .pxl_clk                (pxl_clk),
        .pxl_clk_aresetn        (pxl_clk_aresetn),
        .mouse_x_pos            (mouse_x_pos),
        .mouse_y_pos            (mouse_y_pos),
        .mouse_err              (mouse_err),
        .new_event              (new_event),
        .ps2_pos_tdata          (ps2_pos_tdata), 
        .ps2_pos_tvalid         (ps2_pos_tvalid),
        .ps2_pos_tready         (ps2_pos_tready),
        .mouse_disconnect       (mouse_disconnect)
    );
    
    seven_seg seven_seg_inst (
        .clk    (clk),
        .reset  (reset),
        .seg    (seg),
        .an     (an)
    );
    
    bram_test bram_test_inst (
        .clk                (clk),
        .reset              (reset),
        .addr_max_tdata     (bram_addr_max_tdata),
        .addr_max_tvalid    (bram_addr_max_tvalid),
        .addr_max_tready    (bram_addr_max_tready),
        .seed_tdata         (bram_seed_tdata),
        .seed_tvalid        (bram_seed_tvalid),
        .seed_tready        (bram_seed_tready),
        .status_tdata       (bram_status_tdata),
        .status_tvalid      (bram_status_tvalid),
        .status_tready      (bram_status_tready),
        .error              (bram_error)
    );
endmodule
