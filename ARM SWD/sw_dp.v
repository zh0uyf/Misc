/*------------------------------------------------------------------------------
 CMSIS-DAP SW DP I/O

 Version 1.0 @ 2023/05/01
    1. Initial version
--------------------------------------------------------------------------------*/

module sw_dp(
  swclk,
  swdio
);

output swclk;
inout  swdio;

reg         swclk_o;    /* SWCLK output        */
reg         swdio_oe;   /* SWDIO output enable */
reg         swdio_o;    /* SWDIO output        */
wire        swdio_i;    /* SWDIO input         */

reg         parity;     /* SWD parity          */
reg [2:0]   ack;        /* SWD acknowledge     */
reg [4:0]   state;      /* SWD transfer state  */
reg         bitval;     /* SWD bit value       */
reg [31:0]  sw_rdata;   /* SWD read data       */
reg [31:0]  sw_wdata;   /* SWD write data      */

assign swclk = swclk_o;
assign swdio = swdio_oe ? swdio_o : 1'bz;
assign swdio_i = swdio;

`ifndef SWCLK_DELAY 
`define SWCLK_DELAY       #100ns  /* SWCLK delay time, 5 MHz */
`endif

`ifndef TURNAROUND_CYCLES
`define TURNAROUND_CYCLES 1       /* SWD Turnaround cycles */
`endif

`ifndef IDLE_CYCLES
`define IDLE_CYCLES       8       /* Maximum is 32, caused using in Sequence Task */
`endif

/* SWD Acknowledge */
parameter [2:0]   TRANSFER_OK              = 3'b001;
parameter [2:0]   TRANSFER_WAIT            = 3'b010;
parameter [2:0]   TRANSFER_FAULT           = 3'b100;
/* Transfer State */
parameter [4:0]   TRANSFER_STATE_OK        = 5'h0;
parameter [4:0]   TRANSFER_STATE_ERROR     = 5'h8;
parameter [4:0]   TRANSFER_STATE_MISMATCH  = 5'h10;

/* Transfer APnDP */
parameter         TRANSFER_DP              = 1'b0;
parameter         TRANSFER_AP              = 1'b1;
/* DP address */
parameter [3:0]   DPA00_IDR                = 4'h0;
parameter [3:0]   DPA04_CTRLSTAT           = 4'h4;
parameter [3:0]   DPA08_SELECT             = 4'h8;
parameter [3:0]   DPA0C_RDBUFF             = 4'hC;
/* Bank 0 AP address */
parameter [3:0]   B0AP00_CSW               = 4'h0;
parameter [3:0]   B0AP04_TAR               = 4'h4;
parameter [3:0]   B0AP0C_DRW               = 4'hC;
/* Transfer RnW */
parameter         TRANSFER_WRITE           = 1'b0;
parameter         TRANSFER_READ            = 1'b1;

initial begin
  if (`IDLE_CYCLES > 32) begin
    $display("time is %d, `IDLE_CYCLES larger than 32", $time);
    $finish();
  end
  swdio_oe = 1'b1;
  swdio_o  = 1'b1;
end

/*
 * SWD test connection
 */
task automatic SWD_TestConnect;
begin
  sw_rdata = 32'h0;
  sw_wdata = 32'h0;

  $display("time is %d, SWD_TestConnect: Start ***************************", $time);

  SWJ_Dormant_To_SWD();
  $display("time is %d, SWJ_Dormant_to_SWD: SWJ Dormant to SWD", $time);

  SWJ_LineReset();
  $display("time is %d, SWJ_LineReset: SWJ line reset", $time);

  SWD_Transfer(TRANSFER_DP, TRANSFER_READ, DPA00_IDR, sw_wdata, sw_rdata);
  $display("time is %d, SWD_Transfer: Read IDCODE is %08X(exp. 0BE12477)", $time, sw_rdata);

  SWD_Transfer(TRANSFER_DP, TRANSFER_WRITE, DPA04_CTRLSTAT, 32'h1000_0000, sw_rdata);
  $display("time is %d, SWD_Transfer: Power-up Debug", $time);

  SWD_Transfer(TRANSFER_DP, TRANSFER_WRITE, DPA08_SELECT, 32'h0000_0000, sw_rdata);
  $display("time is %d, SWD_Transfer: Select AP 0", $time);

  SWD_Transfer(TRANSFER_AP, TRANSFER_WRITE, B0AP00_CSW, 32'h0000_0002, sw_rdata);
  $display("time is %d, SWD_Transfer: CSW set access size 32-bit", $time);

  SWD_WriteRegister(32'h3000_8000, 32'h1234_5678);
  $display("time is %d, SWD_WriteRegister: Write 0x12345678 to 0x30008000", $time);

  SWD_ReadRegister(32'h3000_8000, sw_rdata);
  $display("time is %d, SWD_ReadRegister: Read 0x%08X from 0x30008000", $time, sw_rdata);

  $display("time is %d, SWD_TestConnect: End ***************************", $time);
end
endtask

/*
 * Generate clock cycle
 */
task automatic SW_CLOCK_CYCLE;
begin
  swclk_o = 1'b0;
  `SWCLK_DELAY;
  swclk_o = 1'b1;
  `SWCLK_DELAY;
end
endtask

/*
 * Write a bit with clock cycle
 *   ibit: write bit
 */
task automatic SW_WRITE_BIT(input ibit);
begin
  swdio_o = ibit;
  swclk_o = 1'b0;
  `SWCLK_DELAY;
  swclk_o = 1'b1;
  `SWCLK_DELAY;
end
endtask

/*
 * Read a bit form clock cycle
 *   obit: read bit
 */
task automatic SW_READ_BIT(output obit);
begin
  swclk_o = 1'b0;
  `SWCLK_DELAY;
  obit = swdio_i;
  swclk_o = 1'b1;
  `SWCLK_DELAY;
end
endtask

 /*
  * Generate SWJ Sequence
  *   data:   sequence data (LSB first)
  *   count:  sequence bit count (1..32)
  */
task automatic SWJ_Sequence(input [31:0] data, input [5:0] count);
  integer bit_count;
  integer bit_pos;
begin
  bit_count = count;
  bit_pos = 0;
  while (bit_count > 0) begin
    swdio_o = data[bit_pos];
    SW_CLOCK_CYCLE();
    bit_count = bit_count - 1;
    bit_pos = bit_pos + 1;
  end
end
endtask

 /*
  * Generate SWD Write Sequence
  *   data:   sequence data (LSB first)
  *   count:  sequence bit count (1..32)
  */
task automatic SWD_WriteSequence(input [31:0] data, input [5:0] count);
  integer bit_count;
  integer bit_pos;
begin
  bit_count = count;
  bit_pos = 0;
  while (bit_count > 0) begin
    SW_WRITE_BIT(data[bit_pos]);
    bit_count = bit_count - 1;
    bit_pos = bit_pos + 1;
  end
end
endtask

 /*
  * Generate SWD Read Sequence
  *   data:   sequence data (LSB first)
  *   count:  sequence bit count (1..32)
  */
task automatic SWD_ReadSequence(output [31:0] data, input [5:0] count);
  integer bit_count;
  integer bit_pos;
begin
  bit_count = count;
  bit_pos = 0;
  while (bit_count > 0) begin
    SW_READ_BIT(data[bit_pos]);
    bit_count = bit_count - 1;
    bit_pos = bit_pos + 1;
  end
end
endtask

 /*
  * SWD Transfer I/O
  *   APnDP:  1=AP, 0=DP
  *   RnW:    1=Read, 0=Write
  *   A[3:0]: Address
  *   wDATA:  Write Data
  *   rDATA:  Read Data
  */
task automatic SWD_Transfer(input APnDP, input RnW, input [3:0] A, input [31:0] wDATA, output [31:0] rDATA);
  integer i;
begin
  state = TRANSFER_STATE_OK;

  /* Packet Request */
  SW_WRITE_BIT(1'b1);                   /* Start Bit */ 
  SW_WRITE_BIT(APnDP);                  /* APnDP Bit */
  SW_WRITE_BIT(RnW);                    /* RnW Bit */
  SW_WRITE_BIT(A[2]);                   /* A2 Bit */
  SW_WRITE_BIT(A[3]);                   /* A3 Bit */
  parity = APnDP ^ RnW ^ A[2] ^ A[3];   /* Calculate parity */
  SW_WRITE_BIT(parity);                 /* Parity Bit */
  SW_WRITE_BIT(1'b0);                   /* Stop Bit */
  SW_WRITE_BIT(1'b1);                   /* Park Bit */

  /* Turnaround */
  swdio_oe = 1'b0;
  for (i=0; i<`TURNAROUND_CYCLES; i++) begin
    SW_CLOCK_CYCLE();
  end

  /* Acknowledge response */ 
  SW_READ_BIT(ack[0]);                  /* ACK[0] */
  SW_READ_BIT(ack[1]);                  /* ACK[1] */
  SW_READ_BIT(ack[2]);                  /* ACK[2] */

  /*- OK response ------------------------------------------------------------*/
  if (ack == TRANSFER_OK) begin
    /* Data transfer */
    if (RnW == TRANSFER_READ) begin
      /* Read data */
      parity = 1'b0;
      for (i=0; i<32; i++) begin
        SW_READ_BIT(rDATA[i]);
        parity = parity ^ rDATA[i];
      end
      SW_READ_BIT(bitval);             /* Parity Bit */
      if (parity != bitval) begin
        state = TRANSFER_STATE_ERROR;  /* Parity Error, switch to error state */
        $display("time is %d, SWD_Transfer: Parity Error", $time);
      end
      /* Turnaround */
      for (i=0; i<`TURNAROUND_CYCLES; i++) begin
        SW_CLOCK_CYCLE();
      end
      swdio_oe = 1'b1;
    end
    else begin
      /* Turnaround */
      for (i=0; i<`TURNAROUND_CYCLES; i++) begin
        SW_CLOCK_CYCLE();
      end
      swdio_oe = 1'b1;
      /* Write data */
      parity = 1'b0;
      for (i=0; i<32; i++) begin
        SW_WRITE_BIT(wDATA[i]);
        parity = parity ^ wDATA[i];
      end
      SW_WRITE_BIT(parity);            /* Parity Bit */
    end

    /* Idle cycle */
    if (`IDLE_CYCLES > 0) begin
      swdio_o = 1'b0;
      for (i=0; i<`IDLE_CYCLES; i++) begin
        SW_CLOCK_CYCLE();
      end
    end

    $display("time is %d, SWD_Transfer: OK", $time);
    swdio_o = 1'b1;
    return;
  end

  /*- WAIT or FAULT response -------------------------------------------------*/
  if ((ack == TRANSFER_WAIT) || (ack == TRANSFER_FAULT)) begin
    /* WAIT or FAULT response */
    if (RnW == TRANSFER_READ) begin
      /* Dummy Read RDATA[0:31] + Parity */ 
      for (i=0; i<33; i++) begin
        SW_CLOCK_CYCLE();
      end
    end
    /* Turnaround */
    for (i=0; i<`TURNAROUND_CYCLES; i++) begin
      SW_CLOCK_CYCLE();
    end
    swdio_oe = 1'b1;
    if (RnW == TRANSFER_WRITE) begin
      swdio_o = 1'b0;
      /* Dummy Write WDATA[0:31] + Parity */ 
      for (i=0; i<33; i++) begin
        SW_CLOCK_CYCLE();
      end
    end

    $display("time is %d, SWD_Transfer: WAIT or FAULT", $time);
    swdio_o = 1'b1;
    return;
  end

  /*- Protocol error ---------------------------------------------------------*/
  /* Idle cycles */
  for (i=`TURNAROUND_CYCLES+32+1; i>0; i--) begin
    SW_CLOCK_CYCLE();
  end
  /* Enable SWDIO output and set to high */
  swdio_oe = 1'b1;
  swdio_o = 1'b1;
  $display("time is %d, SWD_Transfer: Protocol error", $time);
  return;
end
endtask

/*
 * SWJ Dormant to SWD
 * Switch from Dormant to SWD mode:
 *    1. Send at least 8 SWD clock cycles with SWDIO high. 
 *       It is to ensure the target is not in the middle of detecting a 
 *       Selection Alert sequence.
 *    2. Send 128-bit Selection Alert sequence on SWDIO.
 *       The target is switched out of Dormant state.
 *    3. Send 4 SWCLKTCK cycles with SWDIOTMS LOW. 
 *       The target must ignore the value on SWDIOTMS during these cycles.
 *       This is used to switch next state.
 *    4. Send the ARM CoreSight SW-DP activation code sequence on SWDIOTMS.
 *       The target is switched into SWD mode and an unknown state.
 *       Line reset is required to reset the target into a known state. 
 *    5. Send Idle cycles, it is optional.
 */
task automatic SWJ_Dormant_To_SWD;
begin
  /* At least 8 SWD clock cycles with SWDIO high */
 SWJ_Sequence(32'hFFFF_FFFF, 8);

  /* Selection Alert sequence
  0x49CF9046 A9B4A161 97F5BBC7 45703D98 transmitted MSB first.
  0x19BC0EA2 E3DDAFE9 86852D95 6209F392 transmitted LSB first. */
  SWJ_Sequence(32'h6209_F392, 32);
  SWJ_Sequence(32'h8685_2D95, 32);
  SWJ_Sequence(32'hE3DD_AFE9, 32);
  SWJ_Sequence(32'h19BC_0EA2, 32);

  /* 4 SWD dummy clock cycles 0b0000, switch to next state */
  SWJ_Sequence(32'h0000_0000, 4);

  /* Activation code 0b0101_1000 (ARM CoreSight SW-DP), LSB is 8'h1A. */
  SWJ_Sequence(32'h0000_001A, 8);

  /* Idle cycles */
  SWJ_Sequence(32'h0000_0000, `IDLE_CYCLES);

  swdio_o = 1'b1;
end
endtask

/*
 * SWJ Line Reset
 */
task automatic SWJ_LineReset;
begin
  /* At least 50 SWD clock cycles with SWDIO high */
  SWJ_Sequence(32'hFFFF_FFFF, 32);
  SWJ_Sequence(32'hFFFF_FFFF, 18);

  /* At least two SWD clock cycles with SWDIO low */
  SWJ_Sequence(32'h0000_0000, 2);

  swdio_o = 1'b1;
end
endtask

/*
 * SWJ JTAG-to-SWD sequence
 */
task automatic SWJ_JTAG_To_SWD;
begin
  /* At least 50 SWD clock cycles with SWDIO high */
  SWJ_Sequence(32'hFFFF_FFFF, 32);
  SWJ_Sequence(32'hFFFF_FFFF, 18);

  /* JTAG-to-SWD sequence 0111 1001 1110 0111, LSB is 16'hE97E */
  SWJ_Sequence(32'h0000_E97E, 16);

  /* At least 50 SWD clock cycles with SWDIO high */
  SWJ_Sequence(32'hFFFF_FFFF, 32);
  SWJ_Sequence(32'hFFFF_FFFF, 18);

  swdio_o = 1'b1;
end
endtask

/*
 * SWD write register
 *    address : register address
 *    data    : data to write to register
 */
task automatic SWD_WriteRegister(input [31:0] address, input [31:0] data);
begin
  /* Write TAR with address value */
  SWD_Transfer(TRANSFER_AP, TRANSFER_WRITE, B0AP04_TAR, address, sw_rdata);

  /* Write DRW with data value */
  SWD_Transfer(TRANSFER_AP, TRANSFER_WRITE, B0AP0C_DRW, data, sw_rdata);
end
endtask

/*
 * SWD read register
 *    address : register address
 *    data    : data read from register
 * Note: Two DRW reading is required to read data from register.
 *       First DRW reading is dummy to post next DRW read.
 *       Second DRW reading is actual data read.
 */
task automatic SWD_ReadRegister(input [31:0] address, output [31:0] data);
begin
  /* Write TAR with address value */
  SWD_Transfer(TRANSFER_AP, TRANSFER_WRITE, B0AP04_TAR, address, sw_rdata);

  /* First DRW reading is dummy.
     Read previous AP data and post next AP read */
  SWD_Transfer(TRANSFER_AP, TRANSFER_READ, B0AP0C_DRW, sw_wdata, data); 

  /* Second DRW reading: read data that first DRW reading posted */
  SWD_Transfer(TRANSFER_AP, TRANSFER_READ, B0AP0C_DRW, sw_wdata, data);
end
endtask

endmodule
