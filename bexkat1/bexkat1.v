`timescale 1ns / 1ns

module bexkat1_avalon(input clk,
		      input 	    reset,
		      input 	    avm_waitrequest_n,
		      output 	    avm_write,
		      output 	    avm_read,
		      output [31:0] avm_address,
		      input [31:0]  avm_readdata,
		      output [31:0] avm_writedata,
		      output [3:0]  avm_byteenable,
		      output 	    coe_supervisor,
		      output [3:0]  coe_exception,
		      input [2:0]   inr_irq,
		      output 	    coe_halt,
		      output 	    coe_int_en);

   wire 			    cyc_o, we_o;

   assign avm_write = (cyc_o && we_o);
   assign avm_read = (cyc_o && !we_o);
   
   bexkat1 cpu0(.clk_i(clk), .rst_i(reset), .adr_o(avm_address),
		.ack_i(avm_waitrequest_n), .cyc_o(cyc_o), .we_o(we_o),
		.halt(coe_halt), .inter(inr_irq), .int_en(coe_int_en), 
		.exception(coe_exception), .supervisor(coe_supervisor),
		.dat_i(avm_readdata), .dat_o(avm_writedata),
		.sel_o(avm_byteenable));
   
endmodule

module bexkat1(input 	     clk_i,
	       input 	     rst_i,
	       input 	     ack_i,
	       output [31:0] adr_o,
	       output reg    cyc_o,
	       output reg    we_o,
	       output 	     halt,
	       input [2:0]   inter,
	       output 	     int_en,
	       output [3:0]  exception,
               output 	     supervisor,
	       input [31:0]  dat_i,
	       output [31:0] dat_o,
	       output [3:0]  sel_o);
   
   
`include "bexkat1.vh"
   
   // Control signals
   wire [1:0] 		     reg_write;
   wire [2:0] 		     alu_func;
   wire 		     addrsel, ir_write, vectoff_write,
			     a_write, b_write;
   wire [3:0] 		     reg_read_addr1, reg_read_addr2, reg_write_addr;
   wire [1:0] 		     marsel, ccrsel, spsel, sspsel,
			     alu2sel, statussel;
`ifdef BEXKAT1_FPU
   wire [1:0] 		     fpccrsel;
   wire 		     fp_aeb, fp_alb, fpccr_write;
   wire [2:0] 		     fpu_func;
   wire [31:0] 		     fpu_out;
   wire 		     fp_nan, fp_overflow, fp_underflow, fp_divzero;
   reg [3:0] 		     fpccr, fpccr_next;
`endif
   
   wire [2:0] 		     pcsel, regsel;
   wire [3:0] 		     mdrsel, int_func;
   wire 		     int2sel, superintr;
  
// Data paths
   wire [31:0] 		     alu_out, reg_data_out1, reg_data_out2;
   wire [31:0] 		     ir_next, vectoff_next, dataout, int_out;
   wire 		     alu_carry, alu_negative, alu_overflow, alu_zero; 
   
// Special registers
   reg [31:0] 		     mdr, mdr_next, mar, a, b, pc, ir,
			     busin_be, vectoff;
   reg [32:0] 		     pc_next, mar_next, a_next, b_next;
   reg [31:0] 		     reg_data_in, alu_in2, int_in1, int_in2, intval;
   reg [2:0] 		     ccr, ccr_next;
   reg [3:0] 		     status, status_next;

// opcode format
wire [31:0] ir_sval = { {17{ir[15]}}, ir[15:1] };
wire [31:0] ir_uval = { 17'h0000, ir[15:1] };

// Data switching logic
assign adr_o = (addrsel == ADDR_MAR ? mar : pc);
assign ir_next = (ir_write ? dat_i : ir);
assign vectoff_next = (vectoff_write ? mdr : vectoff);
assign supervisor = (superintr ? 1'b1 : status[3]); // allows us to force supervisor mode w/o changing the bit

   always @(posedge clk_i or posedge rst_i) begin
      if (rst_i) begin
	 pc <= 'h0;
	 ir <= 0;
	 mdr <= 0;
	 mar <= 0;
	 ccr <= 3'h0;
`ifdef BEXKAT1_FPU
	 fpccr <= 4'h0;
`endif
	 vectoff <= 'hffffffc0;
	 status <= 4'b1000; // start in supervisor mode
	 a <= 'h0;
	 b <= 'h0;
      end else begin
	 pc <= pc_next[31:0];
	 ir <= ir_next;
	 mdr <= mdr_next;
	 mar <= mar_next[31:0];
`ifdef BEXKAT1_FPU
	 fpccr <= fpccr_next;
`endif
	 ccr <= ccr_next;
	 vectoff <= vectoff_next;
	 status <= status_next;
	 a <= a_next;
	 b <= b_next;
      end
   end
   
   wire [31:0] exceptionval = vectoff + { exception, 2'b00 };
   
   // All of the datapath options
   always @*
     begin
	case (pcsel)
	  PC_PC:   pc_next = pc;
	  PC_NEXT: pc_next = pc + 'h4;
	  PC_MAR:  pc_next = { 1'b0, mar };
	  PC_REL:  pc_next = { 1'b0, pc } + { ir_sval[29:0], 2'b00 };
	  PC_ALU:  pc_next = { 1'b0, alu_out }; // reg offset
	  PC_EXC: pc_next = { 1'b0, exceptionval };
	  default: pc_next = pc;
	endcase // case (pcsel)
	case (marsel)
	  MAR_MAR: mar_next = mar;
	  MAR_BUS: mar_next = dat_i;
	  MAR_ALU: mar_next = alu_out;
	  MAR_A:   mar_next = a;
	endcase
	case (statussel)
	  STATUS_STATUS: status_next = status;
	  STATUS_SUPER: status_next = { 1'b1, status[2:0] };
	  STATUS_B: status_next = b[3:0];
	  STATUS_POP: status_next = mdr[11:8];
	endcase
	case (mdrsel)
	  MDR_MDR: mdr_next = mdr;
	  MDR_BUS: mdr_next = busin_be; // byte aligned
	  MDR_B:   mdr_next = b;
	  MDR_A:   mdr_next = a;
	  MDR_PC:  mdr_next = pc;
	  MDR_INT: mdr_next = int_out;
`ifdef BEXKAT1_FPU
	  MDR_FPU: mdr_next = fpu_out;
`endif
	  MDR_ALU: mdr_next = alu_out;
	  MDR_CCR: mdr_next = { 20'h0, status, 5'h0, ccr};
	  MDR_STATUS: mdr_next = { 28'h0, status };
	  default: mdr_next = mdr;
	endcase
	case (regsel)
	  REG_ALU:  reg_data_in = alu_out;
	  REG_MDR:  reg_data_in = mdr;
	  REG_UVAL: reg_data_in = ir_uval; // no sign ext
	  REG_B:    reg_data_in = b;
	  default:  reg_data_in = 'h0;
	endcase // case (regsel)
	case (alu2sel)
	  ALU_B:    alu_in2 = b;
	  ALU_SVAL: alu_in2 = ir_sval;
	  ALU_4:    alu_in2 = 4;
	  ALU_1:    alu_in2 = 1;
	endcase
	int_in2 = (int2sel == INT2_SVAL ? ir_sval : b);
	a_next = (a_write ? reg_data_out1 : a);
	b_next = (b_write ? reg_data_out2 : b);
	case (ccrsel)
	  CCR_CCR: ccr_next = ccr;
	  CCR_ALU: ccr_next = { alu_carry, alu_negative ^ alu_overflow, alu_zero };
`ifdef BEXKAT1_FPU
	  CCR_FPU: ccr_next = { fp_alb, fp_alb, fp_aeb };
`else
	  CCR_FPU: ccr_next = ccr;
`endif
	  CCR_MDR: ccr_next = mdr[2:0];
	endcase // case (ccrsel)
`ifdef BEXKAT1_FPU
	fpccr_next =  (fpccr_write
		       ? { fp_nan, fp_overflow, fp_underflow, fp_divzero }
		       : fpccr);
`endif
     end
   
   businterface bus0(.sel(sel_o), .dat_i(dat_i), .dat_o(dat_o),
		     .cpu_o(mdr), .cpu_i(busin_be));

   control con0(.clk_i(clk_i), .rst_i(rst_i), .ir(ir), .ir_write(ir_write),
		.ccr(ccr), .ccrsel(ccrsel), .alu_func(alu_func),
		.a_write(a_write),
		.b_write(b_write), .alu2sel(alu2sel), .regsel(regsel),
		.reg_read_addr1(reg_read_addr1),
		.reg_read_addr2(reg_read_addr2),
		.reg_write_addr(reg_write_addr),
		.reg_write(reg_write), .mdrsel(mdrsel),
		.marsel(marsel), .pcsel(pcsel), .int2sel(int2sel),
		.int_func(int_func),
		.supervisor(supervisor), .addrsel(addrsel),
		.byteenable(sel_o), .statussel(statussel),
		.bus_cyc(cyc_o), .bus_write(we_o), .bus_ack(ack_i),
		.bus_align(adr_o[1:0]),
`ifdef BEXKAT1_FPU
		.fpu_func(fpu_func), 
		.fpccr_write(fpccr_write),
`endif
		.vectoff_write(vectoff_write), .halt(halt),
		.exception(exception), .superintr(superintr),
		.inter(inter), .int_en(int_en));
  
   alu alu0(.clk_i(clk_i), .rst_i(rst_i), .in1(a), .in2(alu_in2),
	    .func(alu_func), .out(alu_out), .c_out(alu_carry),
	    .n_out(alu_negative),
	    .v_out(alu_overflow), .z_out(alu_zero));
   intcalc int0(.clock(clk_i), .func(int_func), .in1(a), .in2(int_in2),
		.out(int_out));
   registerfile intreg(.clk_i(clk_i), .rst_i(rst_i), .supervisor(supervisor),
		       .read1(reg_read_addr1),
		       .read2(reg_read_addr2),
		       .write_addr(reg_write_addr),
		       .write_data(reg_data_in), .write_en(reg_write),
		       .data1(reg_data_out1), .data2(reg_data_out2));

`ifdef BEXKAT1_FPU
   fpu fpu0(.clk_i(clk_i), .rst_i(rst_i), .func(fpu_func), .in1(a),
	    .in2(b), .out(fpu_out),
	    .overflow(fp_overflow), .nan(fp_nan), .underflow(fp_underflow),
	    .divzero(fp_divzero));
   fp_cmp fp_cmp0(.clock(clk_i), .dataa(a), .datab(b), .aeb(fp_aeb),
		  .alb(fp_alb));
`endif
   
endmodule
