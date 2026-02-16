%% BME 526 HW2 - Motor Cortex Decoding Analysis
% Author: Dhyeaya
% Date: February 2025
%
% This script analyzes neural recordings from macaque motor cortex during
% finger movements to:
% 1. Create event-aligned raster plots and PETHs
% 2. Identify response fields for each neuron
% 3. Design decoding thresholds for movement prediction
% 4. Map neurons onto cortical anatomy
%
% Data: 10×10 electrode array in primary motor cortex
% Task: Monkey performs individual and combined finger movements

clear; close all; clc;

%% CONFIGURATION
% Analysis parameters
time_window = [-1, 1];      % Time window around event (seconds)
bin_size = 0.05;            % PETH bin size (50ms)
alignment = 'movement';     % 'cue' or 'movement'
smoothing_window = 3;       % Bins for PETH smoothing

% Neurons to analyze (you can change these)
neurons_to_analyze = [
    54, 1;  % Channel 54, Unit 1
    23, 1;  % Channel 23, Unit 1  
    67, 2;  % Channel 67, Unit 2
];

%% LOAD DATA
fprintf('Loading data...\n');
neural_data = load('BME_526_HW2_NeuralData.mat');
behavior_data = load('BME_526_HW2_BehaviorData.mat');

% Movement types
movements = {'i', 'm', 't', 'im', 'ti', 'tm', 'tim'};
movement_names = {'Index', 'Middle', 'Thumb', 'Index-Middle', ...
                  'Thumb-Index', 'Thumb-Middle', 'Thumb-Index-Middle'};

fprintf('Data loaded successfully!\n');
fprintf('Analyzing %d neurons across %d movement types\n', ...
        size(neurons_to_analyze, 1), length(movements));

%% MAIN ANALYSIS LOOP
for n_idx = 1:size(neurons_to_analyze, 1)
    chan = neurons_to_analyze(n_idx, 1);
    unit = neurons_to_analyze(n_idx, 2);
    
    fprintf('\n========================================\n');
    fprintf('Analyzing Channel %d, Unit %d\n', chan, unit);
    fprintf('========================================\n');
    
    % Get spike times for this neuron
    chan_name = sprintf('Chan%d', chan);
    if ~isfield(neural_data.Channels, chan_name)
        warning('Channel %d not found in data!', chan);
        continue;
    end
    
    chan_data = neural_data.Channels.(chan_name);
    spike_times = chan_data(chan_data(:,2) == unit, 3);
    
    fprintf('Total spikes: %d\n', length(spike_times));
    
    % Create figure for this neuron
    fig = figure('Position', [100, 100, 1400, 900]);
    sgtitle(sprintf('Channel %d, Unit %d - Motor Cortex Response Fields', ...
            chan, unit), 'FontSize', 16, 'FontWeight', 'bold');
    
    % Analyze each movement type
    response_rates = zeros(1, length(movements));
    baseline_rates = zeros(1, length(movements));
    
    for m_idx = 1:length(movements)
        mov = movements{m_idx};
        mov_name = movement_names{m_idx};
        
        % Get event times
        event_var = sprintf('%s_times', mov);
        event_times = behavior_data.(event_var);
        
        % Select alignment (cue = column 1, movement = column 2)
        if strcmp(alignment, 'cue')
            align_times = event_times(:, 1);
        else
            align_times = event_times(:, 2);
        end
        
        % Compute raster and PETH
        [raster, peth, time_bins] = compute_raster_peth(spike_times, ...
            align_times, time_window, bin_size);
        
        % Calculate response metrics
        baseline_idx = time_bins < 0;
        response_idx = time_bins >= 0 & time_bins <= 0.5;
        
        baseline_rates(m_idx) = mean(peth(baseline_idx));
        response_rates(m_idx) = mean(peth(response_idx));
        
        % Plot in subplot (2 rows per movement: raster + PETH)
        row = m_idx;
        
        % Raster plot
        subplot(length(movements), 2, (row-1)*2 + 1);
        plot_raster(raster, time_bins, mov_name);
        if row == 1
            title('Raster Plots', 'FontSize', 12, 'FontWeight', 'bold');
        end
        
        % PETH plot
        subplot(length(movements), 2, (row-1)*2 + 2);
        plot_peth(peth, time_bins, mov_name, baseline_rates(m_idx));
        if row == 1
            title('PETH (Firing Rate)', 'FontSize', 12, 'FontWeight', 'bold');
        end
    end
    
    % Determine response field
    [response_field, modulation] = identify_response_field(response_rates, ...
        baseline_rates, movement_names);
    
    fprintf('\nRESPONSE FIELD ANALYSIS:\n');
    fprintf('Preferred movement: %s\n', response_field);
    fprintf('Modulation index: %.2f\n', modulation);
    
    % Save figure
    saveas(fig, sprintf('results/neuron_chan%d_unit%d.png', chan, unit));
end

%% DECODING ANALYSIS
fprintf('\n========================================\n');
fprintf('DECODING ANALYSIS\n');
fprintf('========================================\n');

% Analyze all 3 neurons together for decoding
fig_decode = figure('Position', [100, 100, 1200, 800]);
sgtitle('Decoder Threshold Selection', 'FontSize', 16, 'FontWeight', 'bold');

decoder_thresholds = zeros(size(neurons_to_analyze, 1), length(movements));

for n_idx = 1:size(neurons_to_analyze, 1)
    chan = neurons_to_analyze(n_idx, 1);
    unit = neurons_to_analyze(n_idx, 2);
    
    chan_name = sprintf('Chan%d', chan);
    chan_data = neural_data.Channels.(chan_name);
    spike_times = chan_data(chan_data(:,2) == unit, 3);
    
    subplot(size(neurons_to_analyze, 1), 1, n_idx);
    hold on;
    
    % Plot PETH for each movement
    colors = lines(length(movements));
    max_rate = 0;
    
    for m_idx = 1:length(movements)
        mov = movements{m_idx};
        event_var = sprintf('%s_times', mov);
        event_times = behavior_data.(event_var);
        align_times = event_times(:, 2); % Movement alignment
        
        [~, peth, time_bins] = compute_raster_peth(spike_times, ...
            align_times, time_window, bin_size);
        
        % Plot smoothed PETH
        peth_smooth = smooth(peth, smoothing_window);
        plot(time_bins, peth_smooth, 'Color', colors(m_idx,:), ...
             'LineWidth', 2, 'DisplayName', movement_names{m_idx});
        
        % Determine threshold (baseline + 2 std)
        baseline_idx = time_bins < 0;
        baseline_mean = mean(peth(baseline_idx));
        baseline_std = std(peth(baseline_idx));
        threshold = baseline_mean + 2 * baseline_std;
        decoder_thresholds(n_idx, m_idx) = threshold;
        
        max_rate = max(max_rate, max(peth_smooth));
    end
    
    % Plot threshold line
    optimal_threshold = median(decoder_thresholds(n_idx, :));
    yline(optimal_threshold, 'r--', 'LineWidth', 2, ...
          'DisplayName', sprintf('Threshold: %.1f Hz', optimal_threshold));
    
    xlabel('Time from Movement (s)');
    ylabel('Firing Rate (Hz)');
    title(sprintf('Channel %d, Unit %d', chan, unit));
    legend('Location', 'best', 'FontSize', 8);
    grid on;
    xlim(time_window);
    ylim([0, max_rate * 1.1]);
end

saveas(fig_decode, 'results/decoder_thresholds.png');

%% SUMMARY REPORT
fprintf('\n========================================\n');
fprintf('DECODER DESIGN SUMMARY\n');
fprintf('========================================\n');

fprintf('\nSelected Neurons for Decoding:\n');
for n_idx = 1:size(neurons_to_analyze, 1)
    chan = neurons_to_analyze(n_idx, 1);
    unit = neurons_to_analyze(n_idx, 2);
    fprintf('  Neuron %d: Channel %d, Unit %d\n', n_idx, chan, unit);
end

fprintf('\nDecoder Thresholds (Hz):\n');
fprintf('%-20s', 'Movement');
for n_idx = 1:size(neurons_to_analyze, 1)
    fprintf(' | Neuron %d', n_idx);
end
fprintf('\n');
fprintf(repmat('-', 1, 60)); fprintf('\n');

for m_idx = 1:length(movements)
    fprintf('%-20s', movement_names{m_idx});
    for n_idx = 1:size(neurons_to_analyze, 1)
        fprintf(' | %8.1f', decoder_thresholds(n_idx, m_idx));
    end
    fprintf('\n');
end

fprintf('\nDECODING STRATEGY:\n');
fprintf('1. Monitor firing rates of all 3 neurons in 50ms bins\n');
fprintf('2. If firing rate exceeds threshold → predict movement\n');
fprintf('3. Combine evidence across neurons for robust decoding\n');
fprintf('4. Each neuron has different response fields → complementary info\n');

fprintf('\n========================================\n');
fprintf('ANALYSIS COMPLETE!\n');
fprintf('Results saved to results/ folder\n');
fprintf('========================================\n');

%% LOCAL FUNCTIONS

function [raster, peth, time_bins] = compute_raster_peth(spike_times, ...
    event_times, time_window, bin_size)
    % Compute event-aligned raster and PETH
    %
    % Inputs:
    %   spike_times - Vector of spike times (seconds)
    %   event_times - Vector of event times to align to (seconds)
    %   time_window - [start, end] relative to event (seconds)
    %   bin_size    - PETH bin width (seconds)
    %
    % Outputs:
    %   raster     - Cell array of spike times per trial
    %   peth       - Peri-event time histogram (firing rate in Hz)
    %   time_bins  - Time bin centers for PETH
    
    n_trials = length(event_times);
    raster = cell(n_trials, 1);
    
    % Extract spikes for each trial
    for trial = 1:n_trials
        event_time = event_times(trial);
        
        % Find spikes in window relative to event
        relative_times = spike_times - event_time;
        in_window = (relative_times >= time_window(1)) & ...
                    (relative_times <= time_window(2));
        
        raster{trial} = relative_times(in_window);
    end
    
    % Compute PETH
    time_bins = time_window(1):bin_size:time_window(2);
    spike_counts = zeros(size(time_bins));
    
    for trial = 1:n_trials
        trial_spikes = raster{trial};
        for spike = trial_spikes'
            bin_idx = find(time_bins <= spike, 1, 'last');
            if ~isempty(bin_idx) && bin_idx <= length(spike_counts)
                spike_counts(bin_idx) = spike_counts(bin_idx) + 1;
            end
        end
    end
    
    % Convert to firing rate (Hz)
    peth = spike_counts / (n_trials * bin_size);
    
    % Center time bins
    time_bins = time_bins + bin_size/2;
    time_bins = time_bins(1:length(peth));
end

function plot_raster(raster, time_bins, movement_name)
    % Plot raster plot for single movement type
    
    hold on;
    n_trials = length(raster);
    
    for trial = 1:n_trials
        trial_spikes = raster{trial};
        if ~isempty(trial_spikes)
            plot(trial_spikes, trial * ones(size(trial_spikes)), ...
                 'k.', 'MarkerSize', 2);
        end
    end
    
    % Event marker
    plot([0, 0], [0, n_trials], 'r-', 'LineWidth', 2);
    
    xlim([time_bins(1), time_bins(end)]);
    ylim([0, n_trials + 1]);
    ylabel(sprintf('%s\nTrial #', movement_name), 'FontWeight', 'bold');
    
    if strcmp(movement_name, 'Thumb-Index-Middle')
        xlabel('Time from Movement (s)');
    else
        set(gca, 'XTickLabel', []);
    end
    
    grid on;
end

function plot_peth(peth, time_bins, movement_name, baseline_rate)
    % Plot PETH with baseline reference
    
    hold on;
    
    % Shade baseline period - FIXED dimension issue
    baseline_idx = time_bins < 0;
    baseline_times = time_bins(baseline_idx);
    baseline_vals = peth(baseline_idx);
    
    % Make sure they're row vectors
    baseline_times = baseline_times(:)';
    baseline_vals = baseline_vals(:)';
    
    if ~isempty(baseline_times)
        fill([baseline_times, fliplr(baseline_times)], ...
             [zeros(size(baseline_times)), fliplr(baseline_vals)], ...
             [0.9, 0.9, 0.9], 'EdgeColor', 'none');
    end
    
    % Plot PETH
    plot(time_bins, peth, 'b-', 'LineWidth', 2);
    
    % Baseline reference
    yline(baseline_rate, 'k--', 'LineWidth', 1.5);
    
    % Event marker
    plot([0, 0], [0, max(peth)*1.1], 'r-', 'LineWidth', 2);
    
    xlim([time_bins(1), time_bins(end)]);
    ylim([0, max(peth) * 1.1]);
    ylabel('Rate (Hz)', 'FontWeight', 'bold');
    
    if strcmp(movement_name, 'Thumb-Index-Middle')
        xlabel('Time from Movement (s)');
    else
        set(gca, 'XTickLabel', []);
    end
    
    grid on;
end

function [response_field, modulation_index] = identify_response_field(...
    response_rates, baseline_rates, movement_names)
    % Identify which movement this neuron responds to most
    %
    % Returns:
    %   response_field    - Name of preferred movement
    %   modulation_index  - Strength of modulation
    
    % Calculate modulation (response - baseline)
    modulation = response_rates - baseline_rates;
    
    % Find strongest response
    [max_mod, max_idx] = max(modulation);
    response_field = movement_names{max_idx};
    
    % Modulation index (normalized)
    modulation_index = max_mod / mean(baseline_rates);
end
