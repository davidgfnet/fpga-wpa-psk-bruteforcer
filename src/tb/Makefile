
toplevel:
	iverilog -o testb.bin -I.. toplevel_tb.v ../toplevel.v ../gen_pipe.v ../sha1_pipe.v ../sha1-post.v ../sha1-pre.v ../uart.v ../cgen.v ../char_map.v ../sha1-small.v ../hash_iterator.v ../ram.v ../hs_fifo.v ../mic_calc.v ../synch.v
	vvp testb.bin -lx2

dual:
	iverilog -o testb.bin -I.. dualtop_tb.v ../toplevel.v ../gen_pipe.v ../sha1_pipe.v ../sha1-post.v ../sha1-pre.v ../uart.v ../cgen.v ../char_map.v ../sha1-small.v ../hash_iterator.v ../ram.v ../hs_fifo.v ../mic_calc.v ../synch.v
	vvp testb.bin -lx2

sha1pipe:
	iverilog -o testb.bin sha1_tb.v ../sha1_pipe.v ../sha1-post.v ../sha1-pre.v
	vvp testb.bin

sha1small:
	iverilog -o testb.bin sha1_small_tb.v ../sha1-small.v
	vvp testb.bin -lx2


cgen:
	iverilog -o testb.bin cgen_tb.v ../cgen.v
	vvp testb.bin -lx2

