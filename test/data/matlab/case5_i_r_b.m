% 3 independent radial networks
% tests shunts

function tppmc = case5_i_r_b

tppmc.baseMVA = 100.0;
tppmc.baseKV = 230.0;

%% bus data
%	bus_i	type	vmin_1	vmax_1	vmin_2	vmax_2	vmin_3	vmax_3	vm_1	va_1	vm_2	va_2	vm_3	va_3
tppmc.bus = [
	1	 2	 0.90	 1.10	 0.90	 1.10	 0.90	 1.10	 1.00000	 2.80377	 1.00000	 2.80377	 1.00000	 2.80377;
	2	 1	 0.90	 1.10	 0.90	 1.10	 0.90	 1.10	 1.08407	-0.73465	 1.08407	-0.73465	 1.08407	-0.73465;
	3	 2	 0.90	 1.10	 0.90	 1.10	 0.90	 1.10	 1.00000	-0.55972	 1.00000	-0.55972	 1.00000	-0.55972;
	4	 3	 0.90	 1.10	 0.90	 1.10	 0.90	 1.10	 1.00000	 0.00000	 1.00000	 0.00000	 1.00000	 0.00000;
	10	 2	 0.90	 1.10	 0.90	 1.10	 0.90	 1.10	 1.00000	 3.59033	 1.00000	 3.59033	 1.00000	 3.59033;
];

%% load data
%	load_bus	pd_1	qd_1	pd_2	qd_2	pd_3	qd_3	status
tppmc.load = [
	2	 300.0	 100.0	 300.0	 100.0	 300.0	 100.0	 1;
	3	 300.0	 100.0	 300.0	 100.0	 300.0	 100.0	 1;
	4	 400.0	 130.0	 400.0	 130.0	 400.0	 130.0	 1;
];

%% shunt data
%	shunt_bus	gs_1	bs_1	gs_2	bs_2	gs_3	bs_3	status
tppmc.shunt = [
	 4	 6.0	 50.0	 5.0	 50.0	 5.0	 50.0	 1;
	10	 2.0	 25.0	 2.0	 25.0	 2.0	 25.0	 1;
];

%% generator data
%	gen_bus	pmin_1	pmax_1	qmin_1	qmax_1	pmin_2	pmax_2	qmin_2	qmax_2	pmin_3	pmax_3	qmin_3	qmax_3	pg_1	qg_1	pg_2	qg_2	pg_3	qg_3	gen_status
tppmc.gen = [
	1	 0.0	  40.0	  -30.0	  30.0	 0.0	  40.0	  -30.0	  30.0	 0.0	  40.0	  -30.0	  30.0	  40.0	  30.0	  40.0	  30.0	  40.0	  30.0	 1;
	1	 0.0	 170.0	 -127.5	 127.5	 0.0 	 170.0	 -127.5	 127.5	 0.0 	 170.0	 -127.5	 127.5	 170.0	 127.5	 170.0	 127.5	 170.0	 127.5	 1;
	3	 0.0	 520.0	 -390.0	 390.0	 0.0 	 520.0	 -390.0	 390.0	 0.0 	 520.0	 -390.0	 390.0	 325.0	 390.0	 325.0	 390.0	 325.0	 390.0	 1;
	4	 0.0	 200.0	 -150.0	 150.0	 0.0	 200.0	 -150.0	 150.0	 0.0	 200.0	 -150.0	 150.0	   0.0	 -10.0	   0.0	 -10.0	   0.0	 -10.0	 1;
	10	 0.0	 600.0	 -450.0	 450.0	 0.0	 600.0	 -450.0	 450.0	 0.0	 600.0	 -450.0	 450.0	 470.0	-165.0	 470.0	-165.0	 470.0	-165.0	 1;
];

%% generator cost data
%	2	startup	shutdown	n	c(n-1)	...	c0
tppmc.gencost = [
	2	 0.0	 0.0	 3	 0.0	 14.0	 0.0;
	2	 0.0	 0.0	 3	 0.0	 15.0	 0.0;
	2	 0.0	 0.0	 3	 0.0	 30.0	 0.0;
	2	 0.0	 0.0	 3	 0.0	 40.0	 0.0;
	2	 0.0	 0.0	 3	 0.0	 10.0	 0.0;
];

%% branch data
%	f_bus	t_bus	r_11	x_11	r_12	x_12	r_13	x_13	r_22	x_22	r_23	x_23	r_33	x_33	rate_a	rate_b	rate_c	angmin	angmax	br_status
tppmc.branch = [
	1	 2	 0.00281	 0.0281	 0.0	 0.0	 0.0	 0.0	 0.00281	 0.0281	 0.0	 0.0	 0.00281	 0.0281	 400	 400	 400	 -30.0	 30.0	 1;
	1	 4	 0.00304	 0.0304	 0.0	 0.0	 0.0	 0.0	 0.00304	 0.0304	 0.0	 0.0	 0.00304	 0.0304	 426	 426	 426	 -30.0	 30.0	 1;
	1	 10	 0.00064	 0.0064	 0.0	 0.0	 0.0	 0.0	 0.00064	 0.0064	 0.0	 0.0	 0.00064	 0.0064	 426	 426	 426	 -30.0	 30.0	 1;
	2	 3	 0.00108	 0.0108	 0.0	 0.0	 0.0	 0.0	 0.00108	 0.0108	 0.0	 0.0	 0.00108	 0.0108	 426	 426	 426	 -30.0	 30.0	 1;
];


% exspected solution per phase
% 
% Objective Cost: 18706.7
%
% Table: bus
%             vm,     va
%       1: 1.031,  0.098
%       2: 1.012,  0.020
%       3: 1.020,  0.020
%       4: 1.013, -0.000
%      10: 1.034,  0.123
%
%
% Table: gen
%             pg,     qg
%       1: 0.400,  0.107
%       2: 1.700,  0.958
%       3: 3.772,  1.913
%       4: 0.000,  0.510
%       5: 4.281, -0.267


