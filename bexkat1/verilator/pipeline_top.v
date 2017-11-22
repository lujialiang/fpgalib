module top(input         clk_i,
	   input 	 rst_i,
	   output [63:0] if_ir,
	   output [63:0] id_ir,
	   output [63:0] exe_ir,
	   output [63:0] mem_ir,
	   output [31:0] if_pc,
	   output [31:0] id_pc,
	   output [31:0] exe_pc,
	   output [31:0] mem_pc,
	   output [31:0] wb_pc,
	   output 	 pc_set,
	   output 	 if_stall,
	   output 	 id_stall,
	   output 	 exe_stall,
	   output 	 mem_stall,
	   output 	 wb_stall,
	   output [31:0] exe_data1,
	   output [31:0] exe_data2,
	   output [31:0] id_reg_data_out1,
	   output [31:0] exe_reg_data_out1,
	   output [31:0] exe_result,
	   output [31:0] mem_result,
	   output [31:0] wb_result,
	   output [31:0] id_reg_data_out2,
	   output [3:0]  wb_reg_write_addr,
	   output [1:0]  id_reg_write,
	   output [1:0]  exe_reg_write,
	   output [1:0]  mem_reg_write,
	   output [1:0]  wb_reg_write,
	   output 	 hazard_stall,
	   output [1:0]  hazard1,
	   output [1:0]  hazard2,
	   output [2:0]  exe_ccr,
	   output [2:0]  mem_ccr);

  logic 		 ins_cyc_o;
  logic 		 ins_ack_i;
  logic [31:0] 		 ins_dat_i;
  logic 		 dat_ack_o;
  logic [31:0] 		 dat_adr_o;
  logic 		 dat_cyc_o;
  logic 		 dat_ack_i;
  logic [31:0] 		 dat_dat_i;
  logic 		 dat_we_o;
  logic [3:0] 		 dat_sel_o;
  logic [31:0] 		 dat_dat_o;
  
  ifetch fetch0(.clk_i(clk_i), .rst_i(rst_i),
		.ir(if_ir),
		.pc(if_pc),
		.stall_i(hazard_stall),
		.stall_o(if_stall),
		.bus_cyc(ins_cyc_o),
		.bus_ack(ins_ack_i),
		.bus_in(ins_dat_i),
		.pc_set(pc_set),
		.pc_in(wb_pc));

  idecode decode0(.clk_i(clk_i), .rst_i(rst_i),
		  .ir_i((hazard_stall ? 64'h0 : if_ir)),
		  .ir_o(id_ir),
		  .stall_i(if_stall),
		  .stall_o(id_stall),
		  .pc_i(if_pc),
		  .pc_o(id_pc),
		  .reg_data_in(wb_result),
		  .reg_write_addr(wb_reg_write_addr),
		  .reg_write_i(wb_reg_write),
		  .reg_write_o(id_reg_write),
		  .reg_data_out1(id_reg_data_out1),
		  .reg_data_out2(id_reg_data_out2));

  
  always_comb
    begin
      case (hazard1)
	2'h1: exe_data1 = mem_result;
	2'h2: exe_data1 = exe_result;
	default: exe_data1 = id_reg_data_out1;
      endcase // case (hazard1)
      case (hazard2)
	2'h1: exe_data2 = mem_result;
	2'h2: exe_data2 = exe_result;
	default: exe_data2 = id_reg_data_out2;
      endcase // case (hazard2)
    end // always_comb
  
  execute exe0(.clk_i(clk_i), .rst_i(rst_i),
	       .reg_data1_i(exe_data1),
	       .reg_data1_o(exe_reg_data_out1),
	       .reg_data2(exe_data2),
	       .result(exe_result),
	       .reg_write_i(id_reg_write),
	       .reg_write_o(exe_reg_write),
	       .stall_i(id_stall),
	       .stall_o(exe_stall),
	       .pc_i(id_pc),
	       .pc_o(exe_pc),
	       .ir_i(id_ir),
	       .ir_o(exe_ir),
	       .ccr_o(exe_ccr));

  forwarder fwd0(.clk_i(clk_i), .rst_i(rst_i),
		 .if_ir(if_ir),
		 .id_ir(id_ir),
		 .id_reg_write(id_reg_write),
		 .exe_ir(exe_ir),
		 .exe_reg_write(exe_reg_write),
		 .mem_ir(mem_ir),
		 .mem_reg_write(mem_reg_write),
		 .stall(hazard_stall),
		 .hazard1(hazard1),
		 .hazard2(hazard2));
		
  mem mem0(.clk_i(clk_i), .rst_i(rst_i),
	   .reg_data1_i(exe_reg_data_out1),
	   .reg_write_i(exe_reg_write),
	   .reg_write_o(mem_reg_write),
	   .result_i(exe_result),
	   .result_o(mem_result),
	   .stall_i(exe_stall),
	   .stall_o(mem_stall),
	   .ir_i(exe_ir),
	   .ir_o(mem_ir),
	   .pc_i(exe_pc),
	   .pc_o(mem_pc),
	   .ccr_i(exe_ccr),
	   .ccr_o(mem_ccr),
	   .bus_adr(dat_adr_o),
	   .bus_cyc(dat_cyc_o),
	   .bus_ack(dat_ack_i),
	   .bus_in(dat_dat_i),
	   .bus_we(dat_we_o),
	   .bus_out(dat_dat_o),
	   .bus_sel(dat_sel_o));
  
  wb wb0(.clk_i(clk_i), .rst_i(rst_i),
	 .ir_i(mem_ir),
	 .pc_set(pc_set),
	 .ccr_i(mem_ccr),
	 .result_i(mem_result),
	 .result_o(wb_result),
	 .pc_i(mem_pc),
	 .pc_o(wb_pc),
	 .stall_i(mem_stall),
	 .stall_o(wb_stall),
	 .reg_write_addr(wb_reg_write_addr),
	 .reg_write_i(mem_reg_write),
	 .reg_write_o(wb_reg_write));

  ram2 #(.AWIDTH(15)) ram0(.clk_i(clk_i), .rst_i(rst_i),
			   .cyc0_i(dat_cyc_o), .stb0_i(1'b1),
			   .sel0_i(dat_sel_o), .we0_i(dat_we_o),
			   .adr0_i(dat_adr_o[16:2]), .dat0_i(dat_dat_i),
			   .dat0_o(dat_dat_o), .ack0_o(dat_ack_o),
			   .cyc1_i(ins_cyc_o), .stb1_i(1'b1),
			   .adr1_i(if_pc[16:2]), .ack1_o(ins_ack_i),
			   .dat1_o(ins_dat_i));
  
endmodule // top