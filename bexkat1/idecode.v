`timescale 1ns / 1ns
`include "bexkat1.vh"
`include "exceptions.vh"

import bexkat1Def::*;

module idecode(input               clk_i,
	       input 		   rst_i,
	       input [63:0] 	   ir_i,
	       input [31:0] 	   pc_i,
	       input [1:0] 	   reg_write,
	       input [3:0] 	   reg_write_addr,
	       input [31:0] 	   reg_data_in,
	       input 		   stall_i,
	       output 		   stall_o,
	       output [63:0] 	   ir_o,
	       output logic [31:0] pc_o,
	       output logic [31:0] reg_data_out1,
	       output logic [31:0] reg_data_out2);
   
  wire [3:0] 			   ir_type = ir_i[31:28];
  wire [3:0] 			   ir_op = ir_i[27:24];
  wire [3:0] 			   ir_ra = ir_i[23:20];
  wire [3:0] 			   ir_rb = ir_i[19:16];
  wire [3:0] 			   ir_rc = ir_i[15:12];
  
  logic [3:0] 			   reg_read1;
  logic [3:0] 			   reg_read2;
  logic [31:0] 			   pc_next;
  logic [63:0] 			   ir_next;
  logic [31:0] 			   reg_data_out1_next;
  logic [31:0] 			   reg_data_out2_next;
  logic [31:0] 			   regfile_out1;
  logic [31:0] 			   regfile_out2;
  
  assign stall_o = stall_i;
  
  always_ff @(posedge clk_i or posedge rst_i)
    begin
      if (rst_i)
	begin
	  pc_o <= 32'h0;
	  ir_o <= 64'h0;
	  reg_data_out1 <= 32'h0;
	  reg_data_out2 <= 32'h0;
	end
      else
	begin
	  pc_o <= pc_next;
	  ir_o <= ir_next;
	  reg_data_out1 <= reg_data_out1_next;
	  reg_data_out2 <= reg_data_out2_next;
	end // else: !if(rst_i)
    end // always_ff @
  
  always_comb
    begin
      if (stall_i)
	begin
	  ir_next = ir_o;
	  pc_next = pc_o;
	  reg_data_out1_next = reg_data_out1;
	  reg_data_out2_next = reg_data_out2;
	end
      else
	begin
	  ir_next = ir_i;
	  pc_next = pc_i;
	  reg_data_out1_next = regfile_out1;
	  reg_data_out2_next = regfile_out2;
	end
      reg_read1 = ir_rb;
      reg_read2 = ir_rc;
      if (ir_type == T_CMP) begin
	reg_read1 = ir_ra;
	reg_read2 = ir_rb;
      end
    end
  
  registerfile reg0(.clk_i(clk_i), .rst_i(rst_i),
		    .supervisor(1'b1),
		    .read1(reg_read1),
		    .read2(reg_read2),
		    .write_addr(reg_write_addr),
		    .write_data(reg_data_in),
		    .write_en(reg_write),
		    .data1(regfile_out1),
		    .data2(regfile_out2));
  
endmodule // idecode
