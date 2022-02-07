module Homelab (
	input         CLK12,
	input         RESET,
	input         CHR64,
	output        HSYNC,
	output        VSYNC,
	output reg    HBLANK,
	output        VBLANK,
	output        VIDEO,
	output reg    AUDIO,
	input         CASS_IN,

	input         KEY_STROBE,
	input         KEY_PRESSED,
	input   [7:0] KEY_CODE, // PS2 keycode

	// DMA bus
	input         DL_CLK,
	input  [15:0] DL_ADDR,
	input   [7:0] DL_DATA,
	input         DL_WE
);

// clock enables
reg cen6, cen3;
reg [1:0] cnt;
always @(posedge CLK12) begin
	cnt <= cnt + 1'd1;
	cen6 <= cnt[0];
	cen3 <= cnt == 0;
end

// video circuit
reg  [8:0] hcnt;
wire       hblank = hcnt[8];
wire       hsync = hblank & hcnt[4] & hcnt[5] & ~hcnt[6];
assign     HSYNC = ~hsync;

reg  [8:0] vcnt;
wire       vblank = vcnt[8];
wire       vsync = vblank & ~vcnt[5] & vcnt[4] & vcnt[3];
assign     VSYNC = ~vsync;
assign     VBLANK = vblank;

always @(posedge CLK12) begin : COUNTERS
	if (cen6) begin
		hcnt <= hcnt + 1'd1;
		if (hcnt == 383) hcnt <= 0;
		if (hcnt == 303) begin // next cycle is hsync
			vcnt <= vcnt + 1'd1;
			if (vcnt == 319) vcnt <= 0;
		end
	end
end

always @(posedge CLK12) begin : BLANK
	if (CHR64 | cen6) begin
		if (hcnt[1:0] == 2'b11 & (CHR64 | hcnt[2])) HBLANK <= hblank;
	end
end

wire        vs_n;
wire [10:0] video_addr = vs_n ? {vcnt[7:3], hcnt[7:2]} : cpu_addr[10:0];

reg   [7:0] vram[2048];
wire [10:0] vram_addr = CHR64 ? video_addr : {1'b0, video_addr[10:1]};
wire        vram_we = ~vs_n & ~wr_n;
reg   [7:0] vram_dout;
/*
// VRAM test pattern
initial begin
	integer i;
	for (i=0;i<2048;i=i+1) begin
		vram[i] = i % 256;
	end
end
*/
always @(posedge CLK12) begin : VRAM
	if (vram_we) vram[vram_addr] <= cpu_dout;
	vram_dout <= vram[vram_addr];
end

reg   [7:0] chrrom[2048];
reg   [7:0] chrrom_dout;
wire [10:0] chrrom_addr = {vcnt[2:0], vram_dout};
always @(posedge CLK12) begin : CHRROM
	chrrom_dout <= chrrom[chrrom_addr];
end

always @(posedge DL_CLK) begin : CHRROM_DL
	if (DL_WE & DL_ADDR[15:11] == 5'b01000) chrrom[DL_ADDR[10:0]] <= DL_DATA;
end

reg   [7:0] video_sr;
assign      VIDEO = video_sr[7];

always @(posedge CLK12) begin : VIDEOSHIFTER
	if (CHR64 | cen6) begin
		if (hcnt[1:0] == 2'b11 & (CHR64 | hcnt[2]) & vs_n & ~vblank & ~hblank) video_sr <= chrrom_dout;
		else video_sr <= {video_sr[6:0], 1'b0};
	end
end

// cpu
wire        int_n = ~vblank;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        iorq_n;
wire        mreq_n;
wire        rfsh_n;
wire        rd_n;
wire        wr_n;

T80s T80 (
	.RESET_n(~RESET),
	.CLK(CLK12),
	.CEN(cen3),
	.WAIT_n(1'b1),
	.INT_n(int_n),
	.NMI_n(1'b1),
	.BUSRQ_n(1'b1),
	.M1_n(),
	.RFSH_n(rfsh_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.A(cpu_addr),
	.DI(cpu_din),
	.DO(cpu_dout)
);

reg   [7:0] rom[16384];
reg   [7:0] rom_dout;
always @(posedge CLK12) begin : ROM
	rom_dout <= rom[cpu_addr[13:0]];
end
always @(posedge DL_CLK) begin : ROM_DL
	if (DL_WE & DL_ADDR[15:14] == 0) rom[DL_ADDR[13:0]] <= DL_DATA;
end

reg   [7:0] ram[16384];
reg   [7:0] ram_dout;
wire        ram_we;
always @(posedge CLK12) begin : RAM
	ram_dout <= ram[cpu_addr[13:0]];
	if (ram_we) ram[cpu_addr[13:0]] <= cpu_dout;
end

reg   [7:0] adec[32];
initial begin
	// 16K ROM/16K RAM
	adec[0] = 8'hBF;
	adec[1] = 8'hBF;
	adec[2] = 8'hDF;
	adec[3] = 8'hDF;
	adec[4] = 8'hEF;
	adec[5] = 8'hEF;
	adec[6] = 8'hF7;
	adec[7] = 8'hF7;
	adec[8] = 8'hFD;
	adec[9] = 8'hFD; 
	adec[10] = 8'hFD;
	adec[11] = 8'hFD;
	adec[12] = 8'hFD;
	adec[13] = 8'hFD;
	adec[14] = 8'hFD;
	adec[15] = 8'hFD;
	adec[16] = 8'hFF;
	adec[17] = 8'hFF;
	adec[18] = 8'hFF;
	adec[19] = 8'hFF;
	adec[20] = 8'hFF;
	adec[21] = 8'hFF;
	adec[22] = 8'hFF;
	adec[23] = 8'hFF;
	adec[24] = 8'hF7;
	adec[25] = 8'hF7;
	adec[26] = 8'hFB;
	adec[27] = 8'hFB;
	adec[28] = 8'h7F;
	adec[29] = 8'h7F;
	adec[30] = 8'hFE;
	adec[31] = 8'hFE;
end

wire  [7:0] adec_q = (~mreq_n & rfsh_n) ? adec[cpu_addr[15:11]] : 8'hFF;
assign cpu_din = ~&adec_q[6:3] ? rom_dout :
                  ~adec_q[1]   ? ram_dout :
                  ~adec_q[0]   ? vram_dout :
                  ~adec_q[7]   ? {4'hF, cpu_addr[4] ? 4'hF : key_matrix[cpu_addr[3:0]]} : 8'h00;
assign ram_we = ~wr_n & ~adec_q[1];
assign vs_n = adec_q[0];

always @(posedge CLK12) begin : BEEP
	reg ks_old;
	ks_old <= adec_q[7];
	if (~ks_old & adec_q[7]) AUDIO <= cpu_addr[7];
end

reg  [3:0] key_matrix[16];

always @(posedge CLK12) begin : KEYBOARD
	if(RESET) begin
		integer i;
		for (i=0;i<16;i=i+1) begin
			key_matrix[i] <= 4'hF;
		end
	end else begin
		key_matrix[2][0] <= vblank;
		key_matrix[3][0] <= CASS_IN;
		if (KEY_STROBE) begin
			case (KEY_CODE)
				8'h72: key_matrix[0][0] <= ~KEY_PRESSED; //down
				8'h75: key_matrix[0][1] <= ~KEY_PRESSED; //up
				8'h74: key_matrix[0][2] <= ~KEY_PRESSED; //right
				8'h6B: key_matrix[0][3] <= ~KEY_PRESSED; //left
				8'h29: key_matrix[1][0] <= ~KEY_PRESSED; //space
				8'h5A: key_matrix[1][1] <= ~KEY_PRESSED; //CR
				8'h12: key_matrix[2][1] <= ~KEY_PRESSED; //lshift
				8'h59: key_matrix[2][2] <= ~KEY_PRESSED; //rshift
				8'h11: key_matrix[2][3] <= ~KEY_PRESSED; //alt
				8'h06: key_matrix[3][1] <= ~KEY_PRESSED; //F2
				8'h05: key_matrix[3][2] <= ~KEY_PRESSED; //F1
				8'h0E: key_matrix[4][0] <= ~KEY_PRESSED; //0
				8'h16: key_matrix[4][1] <= ~KEY_PRESSED; //1
				8'h1E: key_matrix[4][2] <= ~KEY_PRESSED; //2
				8'h26: key_matrix[4][3] <= ~KEY_PRESSED; //3
				8'h25: key_matrix[5][0] <= ~KEY_PRESSED; //4
				8'h2E: key_matrix[5][1] <= ~KEY_PRESSED; //5
				8'h36: key_matrix[5][2] <= ~KEY_PRESSED; //6
				8'h3D: key_matrix[5][3] <= ~KEY_PRESSED; //7
				8'h3E: key_matrix[6][0] <= ~KEY_PRESSED; //8
				8'h46: key_matrix[6][1] <= ~KEY_PRESSED; //9
				8'h54: key_matrix[6][2] <= ~KEY_PRESSED; //:
				8'h5B: key_matrix[6][3] <= ~KEY_PRESSED; //;
				8'h41: key_matrix[7][0] <= ~KEY_PRESSED; //,
				8'h5D: key_matrix[7][1] <= ~KEY_PRESSED; //=
				8'h49: key_matrix[7][2] <= ~KEY_PRESSED; //.
				8'h4A: key_matrix[7][3] <= ~KEY_PRESSED; //?
				8'h76: key_matrix[8][0] <= ~KEY_PRESSED; //Promt
				8'h1C: key_matrix[8][1] <= ~KEY_PRESSED; //A
				8'h52: key_matrix[8][2] <= ~KEY_PRESSED; //Á
				8'h32: key_matrix[8][3] <= ~KEY_PRESSED; //B
				8'h21: key_matrix[9][0] <= ~KEY_PRESSED; //C
				8'h23: key_matrix[9][1] <= ~KEY_PRESSED; //D
				8'h24: key_matrix[9][2] <= ~KEY_PRESSED; //E
				8'h4C: key_matrix[9][3] <= ~KEY_PRESSED; //É
				8'h2B: key_matrix[10][0] <= ~KEY_PRESSED; //F
				8'h34: key_matrix[10][1] <= ~KEY_PRESSED; //G
				8'h33: key_matrix[10][2] <= ~KEY_PRESSED; //H
				8'h43: key_matrix[10][3] <= ~KEY_PRESSED; //I
				8'h3B: key_matrix[11][0] <= ~KEY_PRESSED; //J
				8'h42: key_matrix[11][1] <= ~KEY_PRESSED; //K
				8'h4B: key_matrix[11][2] <= ~KEY_PRESSED; //L
				8'h3A: key_matrix[11][3] <= ~KEY_PRESSED; //M
				8'h31: key_matrix[12][0] <= ~KEY_PRESSED; //N
				8'h44: key_matrix[12][1] <= ~KEY_PRESSED; //O
				8'h55: key_matrix[12][2] <= ~KEY_PRESSED; //Ó
				8'h45: key_matrix[12][3] <= ~KEY_PRESSED; //Ö
				8'h4D: key_matrix[13][0] <= ~KEY_PRESSED; //P
				8'h15: key_matrix[13][1] <= ~KEY_PRESSED; //Q
				8'h2D: key_matrix[13][2] <= ~KEY_PRESSED; //R
				8'h1B: key_matrix[13][3] <= ~KEY_PRESSED; //S
				8'h2C: key_matrix[14][0] <= ~KEY_PRESSED; //T
				8'h3C: key_matrix[14][1] <= ~KEY_PRESSED; //U
				8'h4E: key_matrix[14][2] <= ~KEY_PRESSED; //Ü
				8'h2A: key_matrix[14][3] <= ~KEY_PRESSED; //V
				8'h1D: key_matrix[15][0] <= ~KEY_PRESSED; //W
				8'h22: key_matrix[15][1] <= ~KEY_PRESSED; //X
				8'h35: key_matrix[15][2] <= ~KEY_PRESSED; //Y
				8'h1A: key_matrix[15][3] <= ~KEY_PRESSED; //Z
			endcase
		end
	end
end

endmodule
