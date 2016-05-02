
function [511:0] word_swizzle;
	input [511:0] inword;
	word_swizzle = {
		inword[ 31:  0],
		inword[ 63: 32],
		inword[ 95: 64],
		inword[127: 96],
		inword[159:128],
		inword[191:160],
		inword[223:192],
		inword[255:224],
		inword[287:256],
		inword[319:288],
		inword[351:320],
		inword[383:352],
		inword[415:384],
		inword[447:416],
		inword[479:448],
		inword[511:480]
	};
endfunction
