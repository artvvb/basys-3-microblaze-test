`timescale 1ns / 1ps

module dio_test (
    input  logic        clk,
    input  logic        reset,

    (* IOB = "TRUE" *) inout wire [7:0] ja,
    (* IOB = "TRUE" *) inout wire [7:0] jb,
    (* IOB = "TRUE" *) inout wire [7:0] jc,
    (* IOB = "TRUE" *) inout wire [7:0] jxadc,

    input  logic [31:0] dio_settings_tdata,
    input  logic        dio_settings_tvalid,
    output logic        dio_settings_tready,
    
    output logic [31:0] dio_counter_status_tdata,
    output logic        dio_counter_status_tvalid,
    input  logic        dio_counter_status_tready
);
    typedef enum integer {
        DIO_MODE_IMMUNITY_TOP_TO_BOTTOM, // output on 1-4 of each, input on 7-10 of each
        DIO_MODE_IMMUNITY_PORT_PAIRS, // JA->JXADC, JB->JC
        DIO_MODE_EMISSIONS,
        MODE_OFF
    } DIO_MODE;
    logic       running;
    logic [1:0] valid_samples;
    logic       clock_div_max_valid;
    logic [7:0] clock_div_max;
    logic [7:0] clock_div_count;
    logic       update_output_phase_valid;
    logic [7:0] update_output_phase;
    DIO_MODE    mode;
    logic       mode_valid;
    
    logic        dio_sample_input;
    logic        dio_update_output;
    logic [7:0]  dout_count;
    logic [15:0] din_reg [1:0];
    
    logic [15:0] dout_loop_net;
    logic [15:0] dout_loop [1:0];

    logic [7:0] ja_o;
    logic [7:0] jb_o;
    logic [7:0] jc_o;
    logic [7:0] jxadc_o;

    logic [7:0] ja_t;
    logic [7:0] jb_t;
    logic [7:0] jc_t;
    logic [7:0] jxadc_t;

    logic [7:0] ja_sync_flops    [1:0];
    logic [7:0] jb_sync_flops    [1:0];
    logic [7:0] jc_sync_flops    [1:0];
    logic [7:0] jxadc_sync_flops [1:0];
    logic [15:0] dout_sync_flops [1:0];

    // Control logic input from command parser. Only start DIO test once all config options have been received.
    always_ff @(posedge clk) begin
        if (reset) begin
            clock_div_max_valid <= 0;
        end else if (dio_settings_tvalid) begin
            clock_div_max_valid <= 1;
            clock_div_max <= dio_settings_tdata[7:0];
        end
    end
    
    always_ff @(posedge clk) begin
        if (reset) begin
            update_output_phase_valid <= 0;
        end else if (dio_settings_tvalid) begin
            update_output_phase_valid <= 1;
            update_output_phase <= dio_settings_tdata[15:8];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mode_valid <= 0;
            mode <= MODE_OFF;
        end else if (dio_settings_tvalid) begin
            mode_valid <= 1;
            case (dio_settings_tdata[17:16])
            1: mode <= DIO_MODE_IMMUNITY_TOP_TO_BOTTOM;
            2: mode <= DIO_MODE_IMMUNITY_PORT_PAIRS;
            3: mode <= DIO_MODE_EMISSIONS;
            default: mode <= MODE_OFF;
            endcase
        end
    end
    
    always_comb dio_settings_tready = 1;
    always_comb running = clock_div_max_valid && update_output_phase_valid && mode_valid && (mode != MODE_OFF);

    // Chain clock divider counter and DIO test counter
    always_ff @(posedge clk) begin
        if (reset || !running) begin
            clock_div_count <= 'b0;
        end else begin
            if (clock_div_count == clock_div_max) begin
                clock_div_count <= 'b0;
            end else begin
                clock_div_count <= clock_div_count + 1;
            end
        end
    end

    always_comb dio_sample_input = running && (clock_div_count == clock_div_max);
    always_comb dio_update_output = running && (clock_div_count == update_output_phase);

    always_ff @(posedge clk) begin
        if (reset) begin
            dout_count <= 'b0;
        end else if (dio_update_output) begin
            dout_count <= dout_count + 1;
        end
    end

    // Set I/O signal directions per mode
    always_ff @(posedge clk) begin
        if (mode == DIO_MODE_IMMUNITY_TOP_TO_BOTTOM) begin
            // note: top row outputs are suppressed by tristate buffer
            ja_o <= dout_count;
            ja_t <= 8'hf0;
            jxadc_o <= dout_count;
            jxadc_t <= 8'hf0;
            jb_o <= dout_count;
            jb_t <= 8'hf0;
            jc_o <= dout_count;
            jc_t <= 8'hf0;
            dout_loop_net <= {4{dout_count[3:0]}};
        end else if (mode == DIO_MODE_IMMUNITY_PORT_PAIRS) begin
            ja_o <= dout_count;
            ja_t <= 8'h00;
            jxadc_o <= 8'h00;
            jxadc_t <= 8'hff;
            jb_o <= dout_count;
            jb_t <= 8'h00;
            jc_o <= 8'h00;
            jc_t <= 8'hff;
            dout_loop_net <= {2{dout_count}};
        end else if (mode == DIO_MODE_EMISSIONS) begin
            ja_o <= dout_count;
            ja_t <= 8'h00;
            jxadc_o <= dout_count;
            jxadc_t <= 8'h00;
            jb_o <= dout_count;
            jb_t <= 8'h00;
            jc_o <= dout_count;
            jc_t <= 8'h00;
            dout_loop_net <= 'b0;
        end else begin
            ja_o <= 8'h00;
            ja_t <= 8'h00;
            jb_o <= 8'h00;
            jb_t <= 8'h00;
            jc_o <= 8'h00;
            jc_t <= 8'h00;
            jxadc_o <= 8'h00;
            jxadc_t <= 8'h00;
            dout_loop_net <= 'b0;
        end
    end

    // This isn't an asyncrhonous design - maybe we can kill the sync flops to simplify the hardware loop paths
    logic [7:0] ja_i;
    logic [7:0] jb_i;
    logic [7:0] jc_i;
    logic [7:0] jxadc_i;

    genvar i;
    generate
        for (i=0; i<8; i=i+1) begin
//            // Infer tristate buffers, _t = 1 goes to input
//            assign ja[i] = (ja_t[i]) ? (1'bz) : (ja_o[i]);
//            assign jb[i] = (jb_t[i]) ? (1'bz) : (jb_o[i]);
//            assign jc[i] = (jc_t[i]) ? (1'bz) : (jc_o[i]);
//            assign jxadc[i] = (jxadc_t[i]) ? (1'bz) : (jxadc_o[i]);
           IOBUF #(
              .DRIVE(12), // Specify the output drive strength
              .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE" 
              .IOSTANDARD("DEFAULT"), // Specify the I/O standard
              .SLEW("SLOW") // Specify the output slew rate
           ) ja_IOBUF_inst (
              .O(ja_i[i]),     // Buffer output
              .IO(ja[i]),   // Buffer inout port (connect directly to top-level port)
              .I(ja_o[i]),     // Buffer input
              .T(ja_t[i])      // 3-state enable input, high=input, low=output
           );
           IOBUF #(
              .DRIVE(12), // Specify the output drive strength
              .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE" 
              .IOSTANDARD("DEFAULT"), // Specify the I/O standard
              .SLEW("SLOW") // Specify the output slew rate
           ) jb_IOBUF_inst (
              .O(jb_i[i]),     // Buffer output
              .IO(jb[i]),   // Buffer inout port (connect directly to top-level port)
              .I(jb_o[i]),     // Buffer input
              .T(jb_t[i])      // 3-state enable input, high=input, low=output
           );
           IOBUF #(
              .DRIVE(12), // Specify the output drive strength
              .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE" 
              .IOSTANDARD("DEFAULT"), // Specify the I/O standard
              .SLEW("SLOW") // Specify the output slew rate
           ) jc_IOBUF_inst (
              .O(jc_i[i]),     // Buffer output
              .IO(jc[i]),   // Buffer inout port (connect directly to top-level port)
              .I(jc_o[i]),     // Buffer input
              .T(jc_t[i])      // 3-state enable input, high=input, low=output
           );
           IOBUF #(
              .DRIVE(12), // Specify the output drive strength
              .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE" 
              .IOSTANDARD("DEFAULT"), // Specify the I/O standard
              .SLEW("SLOW") // Specify the output slew rate
           ) jxadc_IOBUF_inst (
              .O(jxadc_i[i]),     // Buffer output
              .IO(jxadc[i]),   // Buffer inout port (connect directly to top-level port)
              .I(jxadc_o[i]),     // Buffer input
              .T(jxadc_t[i])      // 3-state enable input, high=input, low=output
           );
    
            // Resynchronize inputs
            always_ff @(posedge clk) begin
                if (reset || !ja_t[i]) begin
                    ja_sync_flops[0][i] <= 'b0;
                    ja_sync_flops[1][i] <= 'b0;
                end else begin
                    ja_sync_flops[0][i] <= ja_i[i];
                    ja_sync_flops[1][i] <= ja_sync_flops[0][i];
                end
            end
            
            always_ff @(posedge clk) begin
                if (reset || !jb_t[i]) begin
                    jb_sync_flops[0][i] <= 'b0;
                    jb_sync_flops[1][i] <= 'b0;
                end else begin
                    jb_sync_flops[0][i] <= jb_i[i];
                    jb_sync_flops[1][i] <= jb_sync_flops[0][i];
                end
            end
            
            always_ff @(posedge clk) begin
                if (reset || !jc_t[i]) begin
                    jc_sync_flops[0][i] <= 'b0;
                    jc_sync_flops[1][i] <= 'b0;
                end else begin
                    jc_sync_flops[0][i] <= jc_i[i];
                    jc_sync_flops[1][i] <= jc_sync_flops[0][i];
                end
            end
            
            always_ff @(posedge clk) begin
                if (reset || !jxadc_t[i]) begin
                    jxadc_sync_flops[0][i] <= 'b0;
                    jxadc_sync_flops[1][i] <= 'b0;
                end else begin
                    jxadc_sync_flops[0][i] <= jxadc_i[i];
                    jxadc_sync_flops[1][i] <= jxadc_sync_flops[0][i];
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (reset) begin
            dout_sync_flops[0] <= 'b0;
            dout_sync_flops[1] <= 'b0;
        end else begin
            dout_sync_flops[0] <= dout_loop_net;
            dout_sync_flops[1] <= dout_sync_flops[0];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            dout_loop[0] <= 'b0;
            dout_loop[1] <= 'b0;
        end else if (dio_sample_input) begin
            dout_loop[0] <= dout_sync_flops[1];
            dout_loop[1] <= dout_loop[0];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            din_reg[0] <= 'b0;
            din_reg[1] <= 'b0;
        end else if (dio_sample_input) begin
            if (mode == DIO_MODE_IMMUNITY_TOP_TO_BOTTOM) begin
                din_reg[0] <= {jxadc_sync_flops[1][7:4], ja_sync_flops[1][7:4], jb_sync_flops[1][7:4], jc_sync_flops[1][7:4]};
            end else if (mode == DIO_MODE_IMMUNITY_PORT_PAIRS) begin
                din_reg[0] <= {jxadc_sync_flops[1], jc_sync_flops[1]};
            end
            din_reg[1] <= din_reg[0];
        end
    end

    // wait to check for errors in incoming data until there's incoming data to check
    always_ff @(posedge clk) begin
        if (reset || !running) begin
            valid_samples <= 0;
        end else if (dio_sample_input && valid_samples < 2) begin
            valid_samples <= valid_samples + 1;
        end
    end
    
    genvar j;
    generate
        for (j=0; j<16; j=j+1) begin : gen_loop
            logic compare_ne;
            always_comb compare_ne = din_reg[1][j] ^ dout_loop[1][j];
            // check whether internal loopback matches external loopback
            always_ff @(posedge clk) begin
                if (reset || valid_samples == 0) begin
                    dio_counter_status_tdata[j] <= 0;
                end else if (compare_ne) begin
                    dio_counter_status_tdata[j] <= 1;
                end else if (dio_counter_status_tready) begin
                    dio_counter_status_tdata[j] <= 0;
                end
            end
        end
    endgenerate
    always_comb dio_counter_status_tdata[31:18] = 'b0;
    always_comb dio_counter_status_tdata[17] = update_output_phase >= clock_div_max; // all 0 counts as success - phase must be less than divisor
    always_comb dio_counter_status_tdata[16] = !running; // all 0 counts as success - not running is bad
    always_comb dio_counter_status_tvalid = 1;
endmodule