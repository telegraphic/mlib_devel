// #########################################################################################################
// # Project: meerKAT (SKA-SA)
// # Module: flit_gen
// # Coded by: Henno Kriel (henno@ska.ac.za)
// # Date: 25 Feb 2016
// #
// # Description
// #   The purpose of this module is to test the HMC memory, by generating test data 
// #   that is written to the HMC DRAM. The test data is then read back and verified.
// #   This module writes/reads on the same HMC link and only one link.
// #   
// #   This module generates test FLITs for the openHMC AXI interface.
// #   First a HMC 128-byte POSTED WRITE request is generated, then a
// #   HMC 128-byte READ request is issued. The received FLITs are 
// #   decoded and the recovered data is compared to the original written data.
// #
// #   Please consult openHMC document for further info.
// #
// ##########################################################################################################
module flit_gen #(
    //Define width of the datapath
    parameter LINK                  = 0,
    parameter LOG_FPW               = 2,        //Legal Values: 1,2,3
    parameter FPW                   = 4,        //Legal Values: 2,4,6,8
    parameter DWIDTH                = FPW*128,  //Leave untouched
    //Define HMC interface width
    parameter LOG_NUM_LANES         = 3,                //Set 3 for half-width, 4 for full-width
    parameter NUM_LANES             = 2**LOG_NUM_LANES, //Leave untouched
    parameter NUM_DATA_BYTES        = FPW*16           //Leave untouched
  )  (
    input  wire CLK,
    input  wire RST,
    input  wire OPEN_HMC_INIT_DONE,
    output wire [63:0] DATA_RX_FLIT_CNT,
    output wire [63:0] DATA_RX_ERR_FLIT_CNT,
    output wire DATA_ERR_DETECT,
    //----------------------------------
    //----Connect AXI Ports
    //----------------------------------
    //From AXI to HMC Ctrl TX
    output  wire                         s_axis_tx_TVALID,
    input   wire                         s_axis_tx_TREADY,
    output  wire [DWIDTH-1:0]            s_axis_tx_TDATA,
    output  wire [NUM_DATA_BYTES-1:0]    s_axis_tx_TUSER,
    //From HMC Ctrl RX to AXI
    input   wire                         m_axis_rx_TVALID,
    output  wire                         m_axis_rx_TREADY,
    input   wire [DWIDTH-1:0]            m_axis_rx_TDATA,
    input   wire [NUM_DATA_BYTES-1:0]    m_axis_rx_TUSER
  );

// FLIT Layout
// -----------
// 1 FLIT = 128 bits. Thus 4 FLITS per AXI word (512bits)

// AXI Layout: TDATA
// -----------------
// 
// The AXI TDATA is packed as follows:
// [511:384] FLIT3 Processed last
// [383:256] FLIT2
// [255:128] FLIT1
// [127:0]   FLIT0 Processed first

// AXI Layout: TUSER
// -----------------

//TUSER[3:0] - Specifies if valid FLIT is present 
//TUSER[3] - FLIT3 Valid => 1'b1
//TUSER[2] - FLIT2 Valid => 1'b1
//TUSER[1]  - FLIT1 Valid => 1'b1
//TUSER[0]  - FLIT0 Valid => 1'b1

//TUSER[7:4] - Specifies if FLIT Header is present
//TUSER[7] - FLIT3 Header Present => 1'b1
//TUSER[6] - FLIT2 Header Present => 1'b1
//TUSER[5] - FLIT1 Header Present => 1'b1
//TUSER[4] - FLIT0 Header Present => 1'b1

//TUSER[11:8] - Specifies if FLIT Tail is present
//TUSER[11] - FLIT3 Tail Present => 1'b1
//TUSER[10] - FLIT2 Tail Present => 1'b1
//TUSER[9]  - FLIT1 Tail Present => 1'b1
//TUSER[8]  - FLIT0 Tail Present => 1'b1

// AXI Control: 
// TREADY - AXI Bus is ready to accept and process
// TVALID - AXI Bus cycle is active (processs TDATA,TUSER)
// 



// Examples
//
// If the FLIT is a non data FLIT (eg for FLIT0):
// s_axis_tx_TDATA[127:64] is TAIL[63:0]  processed last
// s_axis_tx_TDATA[63:0] is HEADER[63:0]  processed first
//
// If the FLIT is a data FLIT (eg for 32 byte  (256bits) data write):
// Command description             Symbol    CMD Bit  Packet Length in FLITs  Corresponding Response Return
// 32-byte POSTED WRITE request    P_WR32    011001   3                       None (Posted)
//
// FLIT3
// NULL FLIT (Padding) processed last
// s_axis_tx_TDATA[511:384] = 0 
// 
// FLIT2
// s_axis_tx_TDATA[383:320] is Write 32bytes Request (P_WR32) TAIL[63:0]  
// s_axis_tx_TDATA[319:256] is write data [255:192]
//
// FLIT1
// s_axis_tx_TDATA[255:128] is write data [191:64]
//
// FLIT0
// s_axis_tx_TDATA[127:64] is write data [63:0]
// s_axis_tx_TDATA[63:0] is Write 32bytes Request (P_WR32) HEADER[63:0]  processed first


// HEADER LAYOUT
// -------------
// Request Packet Header Layout
// 63:61 CUB[2:0]  Cube ID: CUB field used as an HMC identifier when multiple HMC devices are chained together.

// 60:58 RES[2:0]  Reserved Reserved: These bits are reserved for future address or Cube ID expansion. The responder will ignore bits in this field from 
//                 the requester except for including them in the CRC calculation. The HMC can use portions of this field range internally.
 
// 57:24 ADDR[33:0] Address Request address. For some commands, control fields are included within this range.
// 23:15 TAG[8:0] Tag number uniquely identifying this request.
// 14:11 DLN[3:0] Duplicate of packet length field.
// 10:7  LNG[3:0] Length of packet in FLITs (1 FLIT is 128 bits). Includes header,any data payload, and tail.
// 6 RES [0] Reserved: The responder will ignore this bit from the requester except for including it in the CRC calculation. The HMC can use this field internally.
// 5:0   CMD[5:0]  Packet command. (See Table 19 on page 44 for the list of request commands.)

// TAIL LAYOUT
// -------------
// [63:0] = 0 - The tail must always be set to 0 when requesting - the openHMC core will populate the required fields and CRC


// COMMAND LIST
// ------------

// CMD
// Command description      Symbol  CMD Bit  Packet Length in FLITs  Corresponding Response Return
// 32-byte WRITE request    WR32    001001   3                       WR_RS

// CMD
// Command description             Symbol    CMD Bit  Packet Length in FLITs  Corresponding Response Return
// 32-byte POSTED WRITE request    P_WR32    011001   3                       None (Posted)
// 48-byte POSTED WRITE request    P_WR48    011010   4                       None (Posted)
// 64-byte POSTED WRITE request    P_WR64    011011   5                       None (Posted)
// 96-byte POSTED WRITE request    P_WR96    011101   7                       None (Posted)
// 128-byte POSTED WRITE request   P_WR128   011111   9                       None (Posted)
// Notes: TAG is ignored, No response packet is generated. If an error occurs during the execution of the write request, an Error Response packet will be 
// generated indicating the occurrence of the error to the host.

// CMD
// Command description             Symbol    CMD Bit  Packet Length in FLITs  Corresponding Response Return
// 32-byte READ request            RD32      110001   1                       RD_RS
// 48-byte READ request            RD48      110010   1                       RD_RS
// 64-byte READ request            RD64      110011   1                       RD_RS
// 96-byte READ request            RD96      110101   1                       RD_RS
// 128-byte READ request           RD128     110111   1                       RD_RS


// Signals used in this module
  reg [3:0] wr_flit_state,rd_flit_state;
  reg [27:0] addr;
  //reg [255:0] wr_data,wr_data_chk;
  //reg [255:0] rd_data,rd_data1;
  reg s_axis_tx_TVALID_i;
  reg [DWIDTH-1:0]  s_axis_tx_TDATA_i;
  reg [NUM_DATA_BYTES-1:0] s_axis_tx_TUSER_i;
  reg m_axis_rx_TREADY_i;
  reg [8:0] tag;
  reg [63:0] data_rx_flit_cnt;
  reg [63:0] data_rx_err_flit_cnt;
  reg [3:0] data_err_detect,flit;
  reg [15:0] wait_for_NULL_FLITS_to_complete_cnt;
  reg chk_data;
  reg [1:0] wr_cnt;
  reg next_flit_case1_second;
  reg next_flit_case1_third;
  reg next_flit_case2_second;
  reg next_flit_case2_third;
  reg next_flit_case3_second;
  reg next_flit_case3_third;
  reg next_flit_case4_second;
  reg next_flit_case4_third;
  reg flit_retry;

  // Assign external status ports
  assign DATA_RX_FLIT_CNT = data_rx_flit_cnt;
  assign DATA_RX_ERR_FLIT_CNT = data_rx_err_flit_cnt;
  assign DATA_ERR_DETECT = |data_err_detect;

  assign s_axis_tx_TVALID = s_axis_tx_TVALID_i & s_axis_tx_TREADY;
  assign s_axis_tx_TDATA = s_axis_tx_TDATA_i;
  assign s_axis_tx_TUSER = s_axis_tx_TUSER_i;
  assign m_axis_rx_TREADY = m_axis_rx_TREADY_i;


  // State machine state vector elements
  localparam STATE_IDLE         = 4'd0; // Default state: enter on power up or reset, exit on OPEN_HMC_INIT_DONE == 1'b1
  localparam WAIT_AXI_TX_RDY    = 4'd1; // Wait for AXI TX bus to become available
  localparam STATE_WR_RD_DATA   = 4'd2; // Issue WR128 Request header + write data [447:0]
  localparam STATE_WR_RD_DATA1  = 4'd3; // Write data data [959:448]
  localparam STATE_WR_RD_DATA2  = 4'd4; // Write data data [1023:960], issue WR128 Request tail, issue RD128 Request Header and Tail  
  localparam STATE_CHK_RD_DATA  = 4'd5; // Wait for RX AXI bus to present valid return data and then check it for errors

  // Generate a pseudo random sequence as a function of the supplied tag 
  // This will be used as data for the memory test
  function [1023:0] wr_data_func;
    input [9:0] tag;
    begin
      wr_data_func[63:0]     = {{tag[8:0],tag[9]},~{tag[8:0],tag[9]},{tag[7:0],tag[9:8]},~{tag[7:0],tag[9:8]},tag[9:6],~tag,tag}; // [63:0]     
      wr_data_func[127:64]   = {{tag[6:0],tag[9:7]},~{tag[6:0],tag[9:7]},{tag[5:0],tag[9:6]},~{tag[5:0],tag[9:6]},{tag[4:0],tag[9:5]},~{tag[4:0],tag[9:5]},tag[9:6]}; // [127:64]  
      wr_data_func[191:128]  = {{tag[3:0],tag[9:4]},~{tag[3:0],tag[9:4]},{tag[2:0],tag[9:3]},~{tag[2:0],tag[9:3]},{tag[1:0],tag[9:2]},~{tag[1:0],tag[9:2]},tag[9:6]}; // [191:128]                                                                                                                   7'd0,tag,7'd0,tag,7'd0,tag,7'd0,tag} => Embed tag into data, so that we can use this to check against receive tag for this write req (basic reorder function)
      wr_data_func[255:192]  = {{tag[0:0],tag[9:1]},~{tag[0:0],tag[9:1]},tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},tag[9:6]}; // [255:192] 
      wr_data_func[319:256]  = ~{tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},{tag[7:0],tag[9:8]},~{tag[7:0],tag[9:8]},tag[9:6]}; // [63:0]     
      wr_data_func[383:320]  = ~{{tag[6:0],tag[9:7]},~{tag[6:0],tag[9:7]},{tag[5:0],tag[9:6]},~{tag[5:0],tag[9:6]},{tag[4:0],tag[9:5]},~{tag[4:0],tag[9:5]},tag[9:6]}; // [127:64]  
      wr_data_func[447:384]  = ~{{tag[3:0],tag[9:4]},~{tag[3:0],tag[9:4]},{tag[2:0],tag[9:3]},~{tag[2:0],tag[9:3]},{tag[1:0],tag[9:2]},~{tag[1:0],tag[9:2]},tag[9:6]}; // [191:128]                                                                                                                   7'd0,tag,7'd0,tag,7'd0,tag,7'd0,tag} => Embed tag into data, so that we can use this to check against receive tag for this write req (basic reorder function)
      wr_data_func[511:448]  = ~{{tag[0:0],tag[9:1]},~{tag[0:0],tag[9:1]},tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},tag[9:6]}; // [255:192]
      wr_data_func[575:512]  = {tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},{tag[7:0],tag[9:8]},~{tag[7:0],tag[9:8]},tag[9:6]}; // [63:0]     
      wr_data_func[639:576]  = ~{{tag[6:0],tag[9:7]},~{tag[6:0],tag[9:7]},{tag[5:0],tag[9:6]},~{tag[5:0],tag[9:6]},{tag[4:0],tag[9:5]},~{tag[4:0],tag[9:5]},tag[9:6]}; // [127:64]  
      wr_data_func[703:640]  = {{tag[3:0],tag[9:4]},~{tag[3:0],tag[9:4]},{tag[2:0],tag[9:3]},~{tag[2:0],tag[9:3]},{tag[1:0],tag[9:2]},~{tag[1:0],tag[9:2]},tag[9:6]}; // [191:128]                                                                                                                   7'd0,tag,7'd0,tag,7'd0,tag,7'd0,tag} => Embed tag into data, so that we can use this to check against receive tag for this write req (basic reorder function)
      wr_data_func[767:704]  = ~{{tag[0:0],tag[9:1]},~{tag[0:0],tag[9:1]},tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},tag[9:6]}; // [255:192]
      wr_data_func[831:768]  = ~{~tag,tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},{tag[7:0],tag[9:8]},~{tag[7:0],tag[9:8]},tag[9:6]}; // [63:0]     
      wr_data_func[895:832]  = {{tag[6:0],tag[9:7]},~{tag[6:0],tag[9:7]},{tag[5:0],tag[9:6]},~{tag[5:0],tag[9:6]},{tag[4:0],tag[9:5]},~{tag[4:0],tag[9:5]},tag[9:6]}; // [127:64]  
      wr_data_func[959:896]  = ~{{tag[3:0],tag[9:4]},~{tag[3:0],tag[9:4]},{tag[2:0],tag[9:3]},~{tag[2:0],tag[9:3]},{tag[1:0],tag[9:2]},~{tag[1:0],tag[9:2]},tag[9:6]}; // [191:128]                                                                                                                   7'd0,tag,7'd0,tag,7'd0,tag,7'd0,tag} => Embed tag into data, so that we can use this to check against receive tag for this write req (basic reorder function)
      wr_data_func[1023:960] = {{tag[0:0],tag[9:1]},~{tag[0:0],tag[9:1]},tag,~tag,{tag[8:0],tag[9]},~{tag[8:0],tag[9]},tag[9:6]}; // [255:192]
    end
  endfunction


  // ***************************************************************************************************************************************************************************************
  // Write state machine 
  // Issues posted WR128 and RD128 request FLITs
  // ***************************************************************************************************************************************************************************************
  always @(posedge CLK) begin : wr_flit
  reg [1023:0] wr_data;

  if (RST) begin
    wr_flit_state <= STATE_IDLE;
    addr <= 27'd0; // request addr {2'b00,addr,4b000} [33:32] reserved = "00", 16byte addr, [3:0] reserved 0 (min 16 byte transactions) 
    //wr_data <= 256'h1234_5678_9abc_def0_1002_3004_5006_7008_900A_B00C_D00E_F001_babe_face_dead_0000; // Test vector to be written and read back to/from HMC memory
    s_axis_tx_TVALID_i <= 1'b0; // Deassert all control logic until the HMC is properly initialized
    s_axis_tx_TUSER_i  <= {NUM_DATA_BYTES{1'b0}};
    tag <= 9'd1; // Tag is used to deal with out of order return sequences 
    wait_for_NULL_FLITS_to_complete_cnt <= 16'd0;
    wr_cnt <= 2'd0;
    flit_retry <= 1'b0;

  end else begin
      s_axis_tx_TVALID_i <= 1'b0;
      s_axis_tx_TUSER_i  <= {NUM_DATA_BYTES{1'b0}};
      case (wr_flit_state)
        // State: Entry to state machine (from reset)
        STATE_IDLE: begin
          wr_flit_state <= STATE_IDLE;
          if (LINK==1) begin
            addr[3] <= 1'b1; // odd addresses for LINK1
          end
          if (OPEN_HMC_INIT_DONE == 1'b1) begin // We cannot issue any FLITs if the HMC and the openHMC is not initialized!
            wait_for_NULL_FLITS_to_complete_cnt <= wait_for_NULL_FLITS_to_complete_cnt + 1'b1; // Give some time after the openHMC and HMC have initialize before bomming it with FLITs
          end
          if (wait_for_NULL_FLITS_to_complete_cnt[8] == 1'b1) begin
            wr_flit_state <= WAIT_AXI_TX_RDY; // OK waited long enough => bom it with FLITs
          end
        end
        WAIT_AXI_TX_RDY: begin
          wr_flit_state <= WAIT_AXI_TX_RDY; // Wait for TX AXI FIFO to become available
          if (s_axis_tx_TREADY == 1'b1) begin // Make sure AXI TX FIFO is not FULL  
            wr_flit_state <= STATE_WR_RD_DATA;
          end
        end
        // State: Request WR128 header, followed by write data (WR_REQ_DATA[447:0])
        STATE_WR_RD_DATA: begin
          if (s_axis_tx_TREADY == 1'b1) begin // Make sure AXI TX FIFO is not FULL         
            s_axis_tx_TVALID_i <= 1'b1; // Issue a write to TX AXI FIFO
            //                      WR_REQ_DATA[447:320](s_axis_tx_TDATA_i[511:384]),  WR_REQ_DATA[319:64] (s_axis_tx_TDATA_i[383:128])  , WR_REQ_DATA[63:0] (s_axis_tx_TDATA_i[127:64]),   WR REQ Header (s_axis_tx_TDATA_i[63:0])      
            //s_axis_tx_TDATA_i  <= {{wr_data[127:0],                                    wr_data[255:0],                                     7'd0,tag,7'd0,tag,7'd0,tag,7'd0,tag},            {3'd0,3'd0,{2'd0,addr,4'd0},tag, 4'd9, 4'd9, 1'b0, 6'b011111}}; // posted write req
            wr_data = wr_data_func(tag);
            s_axis_tx_TDATA_i  <= {{wr_data[447:320],                               wr_data[319:64],                                     wr_data[63:0]},                   {3'd0,3'd0,{2'd0,addr,4'd0},tag, 4'd9, 4'd9, 1'b0, 6'b011111}}; // posted write req

            s_axis_tx_TUSER_i[11:0]  <= 12'b0000_0001_1111; // No tails, Header on FLIT0, all FLITS 3-0 valid   
            wr_flit_state <= STATE_WR_RD_DATA1;  // Next round of FLITS
            flit_retry <= 1'b0; // The AXI TX FIFO was not full - FLITS accepted
          end else begin
            if (flit_retry == 1'b0) begin // Uh-oh: The AXI TX FIFO was FULL - FLITS  NOT accepted
              wr_flit_state <= STATE_WR_RD_DATA2; // FIFO was full retry previous write 
              flit_retry <= 1'b1; // issue retry for previous FLITs
            end
          end
        end
        // State: write data (WR_REQ_DATA[959:448])
        STATE_WR_RD_DATA1: begin          
          if (s_axis_tx_TREADY == 1'b1) begin // Make sure AXI TX FIFO is not FULL         
            s_axis_tx_TVALID_i <= 1'b1; // Issue a write to TX AXI FIFO
            //                     WR_REQ_DATA[959:704](s_axis_tx_TDATA_i[511:256]),  WR_REQ_DATA[703:448] (s_axis_tx_TDATA_i[255:0])                
            //s_axis_tx_TDATA_i  <= {wr_data[255:0],                                    wr_data[255:0]}; // posted write req data cont....
            wr_data = wr_data_func(tag);
            s_axis_tx_TDATA_i  <= {wr_data[959:704],                                    wr_data[703:448]}; // posted write req data cont....
            s_axis_tx_TUSER_i[11:0]  <= 12'b0000_0000_1111; // No tails, No headers, all FLITS 3-0 valid (just data) 
            wr_flit_state <= STATE_WR_RD_DATA2; // Next round of FLITS
            flit_retry <= 1'b0; // The AXI TX FIFO was not full - FLITS accepted
          end else begin
            if (flit_retry == 1'b0) begin // Uh-oh: The AXI TX FIFO was FULL - FLITS  NOT accepted 
              wr_flit_state <= STATE_WR_RD_DATA; // FIFO was full retry previous write 
              flit_retry <= 1'b1; // issue retry for previous FLITs
            end
          end
        end
        // State: write data (WR_REQ_DATA[1023:960]), followed by Request WR128 tail, followed by Request RD128 header, followed by Request RD128 tail, followed by 2 NULL FLITs
        STATE_WR_RD_DATA2: begin
          if (s_axis_tx_TREADY == 1'b1) begin // Make sure AXI TX FIFO is not FULL    
            s_axis_tx_TVALID_i <= 1'b1; // Issue a write to TX AXI FIFO
            //                     FLIT3 = NULL FLIT, FLIT2 = NULL FLIT, FLIT1:RD128 Req Tail,  FLIT1: Rd Req Header                                             FLIT0: WR Req Tail   FLIT0: WR_REQ_DATA[1023:960]       
            //s_axis_tx_TDATA_i  <= {128'd0,            128'd0,            {64'd0},               {3'd0,3'd0,{2'd0,addr,4'd0},tag, 4'd1, 4'd1, 1'b0, 6'b110111},   {64'd0},             wr_data[63:0]}; // rd req and posted write req (cont...)
            wr_data = wr_data_func(tag);
            s_axis_tx_TDATA_i  <= {128'd0,            128'd0,            {64'd0},               {3'd0,3'd0,{2'd0,addr,4'd0},tag, 4'd1, 4'd1, 1'b0, 6'b110111},   {64'd0},             wr_data[1023:960]}; // rd req and posted write req (cont...)
            s_axis_tx_TUSER_i[11:0]  <= 12'b0011_0010_0011; // FLIT3 - no tail FLIT2 - no tail FLIT1 tail and header FLIT0 tail, only FLITS 1-0 valid, FLIT 3-2 NULL FLITS (not valid)
            // increment address by two. LINK parameter will determine odd / even
            addr <= addr + 5'b10000; // Granularity: 16bytes (min granularity!) mem addr [3:0] = 0, this is a 128 byte write (ie 8 x 16byte)
            tag <= tag + 1'b1; 
            wr_flit_state <= STATE_WR_RD_DATA; // Next round of FLITS (end of request, start a new WR128 and RD128 request sequence)
            flit_retry <= 1'b0; // The AXI TX FIFO was not full - FLITS accepted
          end else begin
            if (flit_retry == 1'b0) begin // Uh-oh: The AXI TX FIFO was FULL - FLITS  NOT accepted 
              wr_flit_state <= STATE_WR_RD_DATA1; // FIFO was full retry previous write 
              flit_retry <= 1'b1; // issue retry for previous FLITs
            end
          end 
        end       
      endcase
    end    
  end


  // ***************************************************************************************************************************************************************************************
  // Read state machine 
  // Checks incomming memory data from HMC that was requested in the write state machine (WR128 and RD128 request FLITs)
  // ***************************************************************************************************************************************************************************************
  reg [9:0] rd_tag;
  always @(posedge CLK) begin : rd_flit

  reg [1023:0] rd_data;

  if (RST) begin
    // Deassert all control signals on reset
    rd_flit_state <= STATE_IDLE;     // Enter state machine in IDLE state
    m_axis_rx_TREADY_i <= 1'b0;      // Signal to from this module to 
    data_rx_flit_cnt <= 64'd0;       // Count the number of valid FLITs received (data and overheads!)
    data_rx_err_flit_cnt <= 64'd0;   // Count the number of data errors
    data_err_detect <= 4'd0;         // Error detect latch    
    flit <= 4'd0;                    // FLIT index: flit[0] => FLIT0 ... flit[3] => FLIT3
    // For 128byte Requests we need 9 FLITs, this will require 3 AXI (4 FLITs per access) accesses (ie 3 clock cycles)
    next_flit_case1_second <= 1'b0;  // AXI access 2 of 3
    next_flit_case1_third <= 1'b0;   // AXI access 3 of 3
    next_flit_case2_second <= 1'b0;  // AXI access 2 of 3   
    next_flit_case2_third <= 1'b0;   // AXI access 3 of 3    
    next_flit_case3_second <= 1'b0;  // AXI access 2 of 3    
    next_flit_case3_third <= 1'b0;   // AXI access 3 of 3    
    next_flit_case4_second <= 1'b0;  // AXI access 2 of 3    
    next_flit_case4_third <= 1'b0;   // AXI access 3 of 3    

  end else begin
      m_axis_rx_TREADY_i <= 1'b1; // After reset this module is always ready
      next_flit_case1_second <= 1'b0; 
      next_flit_case1_third <= 1'b0;
      next_flit_case2_second <= 1'b0;
      next_flit_case2_third <= 1'b0;
      next_flit_case3_second <= 1'b0;
      next_flit_case3_third <= 1'b0;
      next_flit_case4_second <= 1'b0;
      next_flit_case4_third <= 1'b0;

      // reset FLIT status for each AXI access
      data_err_detect <= 4'd0; 
      flit <= 4'd0; 


      // Start state decoding
      case (rd_flit_state)
        // State: Entry to state machine (from reset)
        STATE_IDLE: begin
          rd_flit_state <= STATE_IDLE;
          if (OPEN_HMC_INIT_DONE == 1'b1) begin
            rd_flit_state <= STATE_CHK_RD_DATA;
          end
        end
        // State: Decode AXI bus and figure out what is data, overheads or NULL FLITs
        //        If there is HMC memory data returned, check this data with the data written to HMC memory in the write state machine 
        STATE_CHK_RD_DATA: begin 

          // 4 FLITs per AXI Access [511:0]:
          //   FLIT0 axis bus [127:0]
          //   FLIT1 axis bus [255:128]
          //   FLIT2 axis bus [383:256]
          //   FLIT3 axis bus [511:384]


          // ****************** First time around FLITs ******************
          // CASE 1 Start
          // Valid FLITSs 3,2,1,0
          // This case follows the same sequence as the WR128 request issued by the write state machine
          // The read data returned will be in the same sequence
          // The RD128 tag that is returned in the FLIT header(m_axis_rx_TDATA[23:15]), must match the tag that was embedded in the data in the WR128 request
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b0000 && m_axis_rx_TUSER[7:4] == 4'b0001 && m_axis_rx_TUSER[3:0] == 4'b1111) begin
            flit[0] <= 1'b1; // Mark FLIT0 as a valid data FLIT, for the FLIT counters
            next_flit_case1_second <= 1'b1; // activate second time around FLITs
            rd_tag <= m_axis_rx_TDATA[23:15];
            //                                      RD128 req tag               RD128 req tag               RD128 req tag               RD128 req tag 
            //if ({wr_data[127:0],wr_data[255:0],7'd0,m_axis_rx_TDATA[23:15],7'd0,m_axis_rx_TDATA[23:15],7'd0,m_axis_rx_TDATA[23:15],7'd0,m_axis_rx_TDATA[23:15]} != m_axis_rx_TDATA[511:64]) begin // Check for errors!
            rd_data = wr_data_func(m_axis_rx_TDATA[23:15]);
            if (rd_data[447:0] != m_axis_rx_TDATA[511:64]) begin // Check for errors!
              data_err_detect[0] <= 1'b1; // Mark this FLIT as having memory data errors, for the FLIT error counters                
            end
          end 

          // CASE 2 Start
          // Valid FLITSs 3,2,1
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:9] == 3'b000 && m_axis_rx_TUSER[7:5] == 3'b001 && m_axis_rx_TUSER[3:1] == 3'b111) begin
            flit[1] <= 1'b1;
            next_flit_case2_second <= 1'b1; // activate second time around FLITs
            rd_tag <= m_axis_rx_TDATA[23+128:15+128];
            //if ({wr_data[255:0],7'd0,m_axis_rx_TDATA[23+128:15+128],7'd0,m_axis_rx_TDATA[23+128:15+128],7'd0,m_axis_rx_TDATA[23+128:15+128],7'd0,m_axis_rx_TDATA[23+128:15+128]} != m_axis_rx_TDATA[511:64+128]) begin // Check for errors!
            rd_data = wr_data_func(m_axis_rx_TDATA[23+128:15+128]);
            if (rd_data[447-128:0] != m_axis_rx_TDATA[511:64+128]) begin // Check for errors!
              data_err_detect[1] <= 1'b1;                 
            end
          end 

          // CASE 3 Start
          // Valid FLITSs 3,2
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:10] == 2'b00 && m_axis_rx_TUSER[7:6] == 2'b01 && m_axis_rx_TUSER[3:2] == 2'b11) begin
            flit[2] <= 1'b1;
            next_flit_case3_second <= 1'b1; // activate second time around FLITs
            rd_tag <= m_axis_rx_TDATA[23+256:15+256];
            //if ({wr_data[127:0],7'd0,m_axis_rx_TDATA[23+256:15+256],7'd0,m_axis_rx_TDATA[23+256:15+256],7'd0,m_axis_rx_TDATA[23+256:15+256],7'd0,m_axis_rx_TDATA[23+256:15+256]} != m_axis_rx_TDATA[511:64+256]) begin // Check for errors!
            rd_data = wr_data_func(m_axis_rx_TDATA[23+256:15+256]);
            if (rd_data[447-256:0] != m_axis_rx_TDATA[511:64+256]) begin // Check for errors!
              data_err_detect[2] <= 1'b1;                 
            end
          end 

          // CASE 4 Start
          // Valid FLITSs 3
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11] == 1'b0 && m_axis_rx_TUSER[7] == 1'b1 && m_axis_rx_TUSER[3] == 1'b1) begin
            flit[3] <= 1'b1;
            next_flit_case4_second <= 1'b1; // activate second time around FLITs
            rd_tag <= m_axis_rx_TDATA[23+384:15+384];
            //if ({7'd0,m_axis_rx_TDATA[23+384:15+384],7'd0,m_axis_rx_TDATA[23+384:15+384],7'd0,m_axis_rx_TDATA[23+384:15+384],7'd0,m_axis_rx_TDATA[23+384:15+384]} != m_axis_rx_TDATA[511:64+384]) begin // Check for errors!
            rd_data = wr_data_func(m_axis_rx_TDATA[23+384:15+384]);
            if (rd_data[447-384:0] != m_axis_rx_TDATA[511:64+384]) begin // Check for errors!
              data_err_detect[3] <= 1'b1;                 
            end
          end 



          // ****************** Second time around FLITs ******************
          // CASE 1 cont...
          // Valid FLITSs 3,2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b0000 && m_axis_rx_TUSER[7:4] == 4'b0000 && m_axis_rx_TUSER[3:0] == 4'b1111 && next_flit_case1_second == 1'b1) begin
            next_flit_case1_third <= 1'b1; // activate third time around FLITs
            //if ({wr_data[255:0],wr_data[255:0]} != m_axis_rx_TDATA[511:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[959:448] != m_axis_rx_TDATA[511:0]) begin // Check for errors!
              data_err_detect[0] <= 1'b1;                 
            end
          end 

          // CASE 2 cont...
          // Valid FLITSs 3,2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b0000 && m_axis_rx_TUSER[7:4] == 4'b0000 && m_axis_rx_TUSER[3:0] == 4'b1111 && next_flit_case2_second == 1'b1) begin
            next_flit_case2_third <= 1'b1; // activate third time around FLITs
            //if ({wr_data[127:0],wr_data[255:0],wr_data[127:0]} != m_axis_rx_TDATA[511:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[959-128:448-128] != m_axis_rx_TDATA[511:0]) begin // Check for errors!
              data_err_detect[1] <= 1'b1;   
            end
          end

          // CASE 3 cont...
          // Valid FLITSs 3,2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b0000 && m_axis_rx_TUSER[7:4] == 4'b0000 && m_axis_rx_TUSER[3:0] == 4'b1111 && next_flit_case3_second == 1'b1) begin
            next_flit_case3_third <= 1'b1; // activate third time around FLITs
            //if ({wr_data[255:0],wr_data[127:0],wr_data[255:128]} != m_axis_rx_TDATA[511:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[959-256:448-256] != m_axis_rx_TDATA[511:0]) begin // Check for errors!
              data_err_detect[2] <= 1'b1;   
            end
          end

          // CASE 4 cont...
          // Valid FLITSs 3,2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b0000 && m_axis_rx_TUSER[7:4] == 4'b0000 && m_axis_rx_TUSER[3:0] == 4'b1111 && next_flit_case4_second == 1'b1) begin
            next_flit_case4_third <= 1'b1; // activate third time around FLITs
            //if ({wr_data[127:0],wr_data[127:0],wr_data[255:0]} != m_axis_rx_TDATA[511:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[959-384:448-384] != m_axis_rx_TDATA[511:0]) begin // Check for errors!
              data_err_detect[3] <= 1'b1;   
            end
          end


          // ****************** Third time around FLITs ******************
          // CASE 1 end
          // Valid FLITSs 0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[8] == 1'b1 && m_axis_rx_TUSER[4] == 1'b0 && m_axis_rx_TUSER[0] == 1'b1 && next_flit_case1_third == 1'b1) begin
            //if ({wr_data[63:0]} != m_axis_rx_TDATA[63:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[1023:960] != m_axis_rx_TDATA[63:0]) begin // Check for errors!
              data_err_detect[0] <= 1'b1;                 
            end
          end 

          // CASE 2 end
          // Valid FLITSs 1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[9:8] == 2'b10 && m_axis_rx_TUSER[5:4] == 2'b00 && m_axis_rx_TUSER[1:0] == 2'b11 && next_flit_case2_third == 1'b1) begin
            //if ({wr_data[63:0],wr_data[255:128]} != m_axis_rx_TDATA[128+63:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[1023:960-128] != m_axis_rx_TDATA[128+63:0]) begin // Check for errors!
              data_err_detect[1] <= 1'b1;                 
            end
          end 

          // CASE 3 end
          // Valid FLITSs 2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[10:8] == 3'b100 && m_axis_rx_TUSER[6:4] == 3'b000 && m_axis_rx_TUSER[2:0] == 3'b111 && next_flit_case3_third == 1'b1) begin
            //if ({wr_data[63:0],wr_data[255:0]} != m_axis_rx_TDATA[256+63:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[1023:960-256] != m_axis_rx_TDATA[256+63:0]) begin // Check for errors!
              data_err_detect[2] <= 1'b1;                 
            end
          end 

          // CASE 4 end
          // Valid FLITSs 3,2,1,0
          if (m_axis_rx_TVALID == 1'b1 && m_axis_rx_TUSER[11:8] == 4'b1000 && m_axis_rx_TUSER[7:4] == 4'b0000 && m_axis_rx_TUSER[3:0] == 4'b1111 && next_flit_case4_third == 1'b1) begin
            //if ({wr_data[63:0],wr_data[255:0],wr_data[255:128]} != m_axis_rx_TDATA[256+128+63:0]) begin // Check for errors!
            rd_data = wr_data_func(rd_tag);
            if (rd_data[1023:960-256-128] != m_axis_rx_TDATA[256+128+63:0]) begin // Check for errors!
              data_err_detect[3] <= 1'b1;                 
            end
          end 


          // If any errors were detected during any of the CASE 1-4 increment the error counters!
          data_rx_err_flit_cnt <= data_rx_err_flit_cnt + data_err_detect[3] + data_err_detect[2] + data_err_detect[1] + data_err_detect[0];
          // Increment received data FLITs!
          data_rx_flit_cnt <= data_rx_flit_cnt + flit[3] + flit[2] + flit[1] + flit[0];
          
        end
      endcase
    end    
  end

endmodule