function power_behav(BitWidth, add_latency, mult_latency)
%% inports
xlsub3_c = xInport('c');

%% outports
xlsub3_power = xOutport('power');

%% diagram

% block: single_pol/spect_power/power/c_to_ri
xlsub3_c_to_ri_out1 = xSignal;
xlsub3_c_to_ri_out2 = xSignal;
xlsub3_c_to_ri = xBlock(struct('source', 'casper_library_misc/c_to_ri', 'name', 'c_to_ri'), ...
                        struct('n_bits', BitWidth, ...
                               'bin_pt', BitWidth-1), ...
                        {xlsub3_c}, ...
                        {xlsub3_c_to_ri_out1, xlsub3_c_to_ri_out2});

% block: single_pol/spect_power/power/imag_square
xlsub3_imag_square_out1 = xSignal;
xlsub3_imag_square = xBlock(struct('source', 'Mult', 'name', 'imag_square'), ...
                            struct('n_bits', 8, ...
                                   'bin_pt', 2, ...
                                   'latency', mult_latency, ...
                                   'placement_style', 'Rectangular shape'), ...
                            {xlsub3_c_to_ri_out2, xlsub3_c_to_ri_out2}, ...
                            {xlsub3_imag_square_out1});

% block: single_pol/spect_power/power/power_adder
xlsub3_real_square_out1 = xSignal;
xlsub3_power_adder = xBlock(struct('source', 'AddSub', 'name', 'power_adder'), ...
                            struct('latency', add_latency, ...
                                   'precision', 'User Defined', ...
                                   'n_bits', BitWidth * 2, ...
                                   'bin_pt', BitWidth * 2 - 1, ...
                                   'use_behavioral_HDL', 'on', ...
                                   'use_rpm', 'on'), ...
                            {xlsub3_real_square_out1, xlsub3_imag_square_out1}, ...
                            {xlsub3_power});

% block: single_pol/spect_power/power/real_square
xlsub3_real_square = xBlock(struct('source', 'Mult', 'name', 'real_square'), ...
                            struct('n_bits', 8, ...
                                   'bin_pt', 2, ...
                                   'latency', mult_latency, ...
                                   'placement_style', 'Rectangular shape'), ...
                            {xlsub3_c_to_ri_out1, xlsub3_c_to_ri_out1}, ...
                            {xlsub3_real_square_out1});



end

