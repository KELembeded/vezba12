`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/29/2018 12:47:31 AM
// Design Name: 
// Module Name: VGA
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


module VGA# 
  (
   )
   (
    //globals
    input logic           clk,
    input logic           reset,
    //vga interface
    output logic          hsync,
    output logic          vsync,
    output logic [15 : 0] rgb,
    //dma interface
    input logic [15:0]    sdata,
    input logic           svalid,
    output logic          sready,
    input logic           slast
    );

   typedef enum           logic[0:0]{not_synced, synced} states;
   states state_reg, state_next;

   logic                  clk_en=0;
   //constants
   localparam integer     CLK_DIV_VAL = 4;
   localparam logic [9:0] h_end = 800;
   localparam logic [9:0] h_left_boundary = 48;
   localparam logic [9:0] h_right_boundary = 16;
   localparam logic [9:0] h_writeback = 96;
   localparam logic [9:0] h_image = 640;

   localparam logic [9:0] v_end = 525;
   localparam logic [9:0] v_bottom_boundary = 10;
   localparam logic [9:0] v_upper_boundary = 33;
   localparam logic [9:0] v_writeback = 2;
   localparam logic [9:0] v_image = 480;

   localparam logic [9:0] v_resolution = 480;
   localparam logic [9:0] h_resolution = 640;
   // registers
   logic [9:0]            h_counter_reg, h_counter_next;
   logic [9:0]            v_counter_reg, v_counter_next;   
   
   logic                  hsync_reg, hsync_next;
   logic                  vsync_reg, vsync_next;
   logic                  sready_reg, sready_next;
   logic [$clog2(CLK_DIV_VAL):0] clock_divider_reg, clock_divider_next;
   //sequential logic
   always_ff @(posedge clk)
     begin
        if (!reset) 
          begin
             clock_divider_reg <= 0;
             h_counter_reg <= 0;
             v_counter_reg <= 0;         
             hsync_reg <= 0;
             vsync_reg <= 0;
             state_reg <= not_synced;
             sready_reg <= 0;            
          end
        else 
          begin
             clock_divider_reg <= clock_divider_next;
             h_counter_reg <= h_counter_next;
             v_counter_reg <= v_counter_next;
             hsync_reg <= hsync_next;
             vsync_reg <= vsync_next;
             state_reg <= state_next;
             sready_reg <= sready_next;           
          end
     end
   //clock divider counter *** generate next state and clock enable
   always_comb
     begin
        clk_en = 1'b0;
        clock_divider_next = clock_divider_reg;      
        if(clock_divider_reg == (CLK_DIV_VAL - 1))
          begin
             clock_divider_next = 0;
             clk_en = 1'b1;             
          end
        else 
          begin
             clock_divider_next = clock_divider_reg + 1;                 
             clk_en = 1'b0;             
          end            
     end
   //horizontal counter *** generate next state 
   always_comb 
     begin
        h_counter_next = h_counter_reg;      
        if (clk_en == 1) 
          begin
             if (h_counter_reg == (h_end - 1))
               begin
                  h_counter_next = 0;
               end
             else
               begin
                  h_counter_next = h_counter_reg + 1;
               end
          end
     end
   //vertical counter *** generate next state 
   always_comb
     begin
        v_counter_next = v_counter_reg;      
        if ((clk_en == 1) && (h_counter_reg == (h_end - 1)))
          begin
             if (v_counter_reg == (v_end - 1))
               begin
                  v_counter_next = 0;            
               end
             else
               begin
                  v_counter_next = v_counter_reg + 1;        
               end
          end
     end
   //horizontal sync signal register *** generate next state 
   always_comb
     begin
        hsync_next = hsync_reg;
        // 655 <= h_counter <= 751
        if (h_counter_reg >= (h_image + h_right_boundary) && h_counter_reg <= (h_image + h_right_boundary + h_writeback - 1))
          begin
             hsync_next = 1'b0;
          end
        else
          begin
             hsync_next = 1'b1;
          end
     end
   //vertical sync signal register *** generate next state 
   always_comb
     begin
        vsync_next = vsync_reg;
        // 490 <= h_counter <= 491
        if ((v_counter_reg >= (v_image + v_bottom_boundary)) && (v_counter_reg <= (v_image + v_bottom_boundary + v_writeback - 1)))
          begin
             vsync_next = 1'b0;         
          end
        else
          begin
             vsync_next = 1'b1;
          end
     end
   //combinational logic used to generate sready signal needed by DMA
   always_comb
     begin
        sready_next = 0;

        case (state_reg)

          not_synced:
            begin
               sready_next = 0;
            end
          synced:
            begin
	       if(clk_en==1'b1 && svalid==1'b1 && h_counter_next < h_image && v_counter_next < v_image)
		 sready_next = 1;   
            end
        endcase
     end

   //combinational logic for rgb 
   always_comb
     begin	
	rgb = 0;
	if (state_reg==synced && (h_counter_reg < h_resolution -1) && (v_counter_reg < v_resolution-1))             
	  begin
	     rgb = sdata;                           
	  end
     end

   //combinational logic used for synchronization of DMA and VGA
   always_comb
     begin	
	state_next = state_reg;        

	case (state_reg)
	  not_synced:             
	    begin
	       //Wait in this state until h_counter == 0 and v_counter == 0. When  that happens
	       // DMA can start sending piksels, and FSM state changes to synced.
	       if(svalid == 1 && (h_counter_reg == h_end - 1) && (v_counter_reg == v_end - 1))             
		 state_next = synced; 
	    end
	  synced:
	    begin
               //checks if DMA and VGA are synced. If h_counter == 639, v_conter == 479 and DMA has
	       //sent the last piksel of an image they are in sync.
	       if(slast && (h_counter_next != h_image - 1) && (v_counter_next != v_image - 1))
		 begin
		    state_next = not_synced;
		 end
	    end // case: synced
	endcase
     end

   assign vsync = vsync_reg;
   assign hsync = hsync_reg;
   assign sready = sready_reg;

endmodule
