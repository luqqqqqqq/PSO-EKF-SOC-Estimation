function result = run_experiment(battery, cycle, method, varargin)
%RUN_EXPERIMENT Run one case with the parameter groups stored in PSOmodel.
%   result = run_experiment('C', 'NEDC', 'PSO')
%   result = run_experiment('A', 'HPPC', 'G1', ...
%       'StopTime', 20000, 'MetricWindow', [10000 20000])
%
% Battery: A, B, C. Cycle: HPPC, NEDC, FUDS. Method: G1, G0, PSO, FIXED.
% FIXED accepts the name-value argument 'FixedGain', G (default 1).
% Set 'WriteResults', false for an in-memory run, such as a gain search.
% StopTime defaults to the last measurement timestamp. MetricWindow must be
% supplied explicitly to calculate metrics; no paper evaluation window is
% assumed. G0 switches off the EKF correction only in the model's plateau
% interval. PSO uses the stored offline gain schedules, without retraining.
%
% Changes are confined to the loaded model in memory. This function never
% saves the model or writes G/PSO to the base workspace. MATLAB R2023a,
% Simulink and Stateflow are required. This release was statically checked;
% the entry point has not been executed in MATLAB by the release maintainer.

    battery = validatestring(battery, {'A', 'B', 'C'});
    cycle = validatestring(cycle, {'HPPC', 'NEDC', 'FUDS'});
    method = validatestring(method, {'G1', 'G0', 'PSO', 'FIXED'});
    parser = inputParser;
    parser.addParameter('StopTime', [], @(x) isempty(x) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    parser.addParameter('MetricWindow', [], @(x) isempty(x) || ...
        (isnumeric(x) && isvector(x) && numel(x) == 2 && ...
        all(isfinite(x)) && x(1) >= 0 && x(2) > x(1)));
    parser.addParameter('FixedGain', 1, @(x) isnumeric(x) && isscalar(x) && ...
        isfinite(x) && x >= 0);
    parser.addParameter('OutputDir', '', @(x) ischar(x) || ...
        (isstring(x) && isscalar(x)));
    parser.addParameter('WriteResults', true, @(x) islogical(x) && isscalar(x));
    parser.parse(varargin{:});
    options = parser.Results;

    root = fileparts(fileparts(mfilename('fullpath')));
    dataDir = fullfile(root, 'data', 'mat');
    model = 'PSOmodel';
    modelFile = fullfile(root, 'src', 'models', [model '.slx']);
    assert(isfile(modelFile), 'Release:MissingModel', 'Missing PSOmodel.slx.');
    if bdIsLoaded(model)
        error('Release:ModelAlreadyLoaded', ...
            ['PSOmodel is already loaded. Save your work and close it ' ...
             'before running this entry point.']);
    end

    batteryNumber = double(battery) - double('A') + 1;
    prefix = sprintf('%d_%s', batteryNumber, cycle);
    currentFile = fullfile(dataDir, [prefix '_I.mat']);
    voltageFile = fullfile(dataDir, [prefix '_V.mat']);
    current = load(currentFile, 'i');
    voltage = load(voltageFile, 'v');
    check_measurement(current.i, 'current');
    check_measurement(voltage.v, 'voltage');
    assert(isequal(current.i(1,:), voltage.v(1,:)), ...
        'Release:TimeMismatch', 'Current and voltage timestamps differ.');
    lastTime = current.i(1,end);
    stopTime = options.StopTime;
    if isempty(stopTime)
        stopTime = lastTime;
    end
    assert(stopTime <= lastTime, 'Release:StopTimeOutOfRange', ...
        'StopTime must not exceed the last measurement timestamp (%g s).', lastTime);
    if ~isempty(options.MetricWindow)
        assert(options.MetricWindow(2) <= stopTime, ...
            'Release:MetricWindowOutOfRange', ...
            'MetricWindow must be within the simulated interval.');
    end

    fileGenConfig = Simulink.fileGenControl('getConfig');
    restoreFileGen = onCleanup(@() Simulink.fileGenControl( ...
        'setConfig', 'config', fileGenConfig)); %#ok<NASGU>
    Simulink.fileGenControl('set', ...
        'CacheFolder', fullfile(root, 'build', 'cache'), ...
        'CodeGenFolder', fullfile(root, 'build', 'codegen'), 'createDir', true);
    load_system(modelFile);
    closeOwnedModel = onCleanup(@() close_owned_model(model)); %#ok<NASGU>

    % Resolve even disconnected source blocks without changing MATLAB's path.
    sourceBlocks = find_system(model, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'FromFile');
    for k = 1:numel(sourceBlocks)
        [~, stem, extension] = fileparts(get_param(sourceBlocks{k}, 'FileName'));
        if isempty(extension), extension = '.mat'; end
        resolvedFile = fullfile(dataDir, [stem extension]);
        assert(isfile(resolvedFile), 'Release:MissingInput', ...
            'A model input is missing: %s%s.', stem, extension);
        set_param(sourceBlocks{k}, 'FileName', resolvedFile);
    end
    % These are the two connected sources in the archived PSOmodel.
    set_param([model '/19935s'], 'FileName', currentFile);
    set_param([model '/realtime voltage5'], 'FileName', voltageFile);
    parameterSnapshot = select_battery_parameters(model, batteryNumber);

    switch method
        case 'G1', gain = 1; psoDisabled = 1;
        case 'G0', gain = 0; psoDisabled = 1;
        case 'PSO', gain = 1; psoDisabled = 0;
        case 'FIXED', gain = options.FixedGain; psoDisabled = 1;
    end
    simulation = Simulink.SimulationInput(model);
    simulation = simulation.setVariable('G', gain);
    simulation = simulation.setVariable('PSO', psoDisabled);
    simulation = simulation.setModelParameter('StartTime', '0', ...
        'StopTime', num2str(stopTime, 17), 'ReturnWorkspaceOutputs', 'on');
    output = sim(simulation);

    estimate = output.get('model_soc');
    reference = output.get('real_soc');
    errorSeries = output.get('err_soc');
    assert(isequal(estimate.Time, reference.Time, errorSeries.Time), ...
        'Release:OutputTimeMismatch', 'Logged output timestamps differ.');
    time = estimate.Time(:);
    estimateData = estimate.Data(:);
    referenceData = reference.Data(:);
    errorData = errorSeries.Data(:);
    assert(all(isfinite([time; estimateData; referenceData; errorData])), ...
        'Release:NonfiniteOutput', 'Simulation produced a nonfinite output.');
    assert(max(abs(errorData - (estimateData - referenceData))) < 1e-8, ...
        'Release:UnexpectedErrorDefinition', 'SOC error is not estimate minus reference.');
    series = table(time, referenceData, estimateData, errorData, ...
        'VariableNames', {'time_s', 'soc_reference_pct', ...
        'soc_estimated_pct', 'soc_error_pp'});

    metrics = struct([]);
    if ~isempty(options.MetricWindow)
        selected = time >= options.MetricWindow(1) & time <= options.MetricWindow(2);
        assert(any(selected), 'Release:EmptyMetricWindow', ...
            'The requested window contains no logged samples.');
        values = errorData(selected);
        metrics = struct('requested_window_s', options.MetricWindow(:)', ...
            'first_sample_s', time(find(selected, 1, 'first')), ...
            'last_sample_s', time(find(selected, 1, 'last')), ...
            'sample_count', nnz(selected), 'mae_pp', mean(abs(values)), ...
            'mse_pp2', mean(values.^2), 'rmse_pp', sqrt(mean(values.^2)), ...
            'max_abs_error_pp', max(abs(values)));
    end

    caseName = sprintf('%s_%s_%s', battery, cycle, method);
    result = struct('case', caseName, 'series', series, 'metrics', metrics, ...
        'parameters', parameterSnapshot, 'csv_file', '', 'metadata_file', '');
    if ~options.WriteResults, return; end

    outputDir = char(options.OutputDir);
    if isempty(outputDir), outputDir = fullfile(root, 'build', 'results'); end
    % A separate folder prevents an earlier run or a different window being overwritten.
    if ~isfolder(outputDir), mkdir(outputDir); end
    caseDir = tempname(outputDir);
    mkdir(caseDir);
    csvFile = fullfile(caseDir, [caseName '_timeseries.csv']);
    writetable(series, csvFile);
    manifest = struct('case', caseName, 'battery', battery, 'cycle', cycle, ...
        'method', method, 'G', gain, 'PSO_disabled', psoDisabled, ...
        'model', 'PSOmodel', 'matlab_release', version('-release'), ...
        'stop_time_s', stopTime, 'measurement_end_s', lastTime, ...
        'metric_window_s', options.MetricWindow, 'metrics', metrics, ...
        'parameters', parameterSnapshot, ...
        'note', ['Rerun with the parameter group stored in the released model. ' ...
        'The result is not asserted to match a published table.']);
    jsonFile = fullfile(caseDir, [caseName '_run.json']);
    file = fopen(jsonFile, 'w', 'n', 'UTF-8');
    assert(file >= 0, 'Release:OutputWriteFailed', 'Could not create run metadata.');
    closeFile = onCleanup(@() fclose(file)); %#ok<NASGU>
    fprintf(file, '%s\n', jsonencode(manifest, 'PrettyPrint', true));
    result.csv_file = csvFile;
    result.metadata_file = jsonFile;
    fprintf('Completed %s. Results: %s\n', caseName, caseDir);
end

function snapshot = select_battery_parameters(model, batteryNumber)
% Copy the selected stored group into the already connected Battery C blocks.
% Do not mix parameters from EKFmodel or infer values from block names.
    subsystem = [model '/EKF'];
    parameterNames = {'R0', 'R1', 'C1', 'R2', 'C2'};
    sourceTables = { ...
        {'1-D-R3',  '1-D-R6',  '1-D-R1', '1-D-R5',  '1-D-C4'}; ...
        {'1-D-R7',  '1-D-R8',  '1-D-C7', '1-D-R9',  '1-D-C8'}; ...
        {'1-D-R10', '1-D-R11', '1-D-C9', '1-D-R12', '1-D-C10'}};
    targetTables = sourceTables{3};
    tableProperties = {'Table', 'BreakpointsForDimension1', 'InterpMethod', 'ExtrapMethod'};
    tableValues = cell(5, numel(tableProperties));
    for k = 1:5
        source = [subsystem '/' sourceTables{batteryNumber}{k}];
        for property = 1:numel(tableProperties)
            tableValues{k,property} = get_param(source, tableProperties{property});
        end
    end
    ocvBlocks = {'soc-ocv-15order_new', 'soc-ocv-15order_new1', 'soc-ocv-15order_new2'};
    derivativeBlocks = {'soc-ocv-15order_new5', 'soc-ocv-15order_new4', 'soc-ocv-15order_new3'};
    capacityBlocks = {'1_As', '2_As', '3_As'};
    % For A, 1_As is wired to the capacity tag; 1_As1 is a disconnected alternative.
    capacity = get_param([subsystem '/' capacityBlocks{batteryNumber}], 'Value');
    ocv = get_param([subsystem '/' ocvBlocks{batteryNumber}], 'Expr');
    derivative = get_param([subsystem '/' derivativeBlocks{batteryNumber}], 'Expr');
    measurementNoise = get_param([subsystem '/' num2str(batteryNumber) '_观测噪声1'], 'Value');
    processNoise = get_param([subsystem '/' num2str(batteryNumber) '_过程噪声1'], 'Value');
    snapshot = struct('source_battery_group', batteryNumber, ...
        'capacity_As_expression', capacity, 'measurement_noise_expression', measurementNoise, ...
        'process_noise_expression', processNoise, 'ocv_expression', ocv, ...
        'ocv_derivative_expression', derivative);
    for k = 1:5
        target = [subsystem '/' targetTables{k}];
        for property = 1:numel(tableProperties)
            set_param(target, tableProperties{property}, tableValues{k,property});
        end
        snapshot.(parameterNames{k}) = struct('table', tableValues{k,1}, ...
            'breakpoints', tableValues{k,2}, 'interpolation', tableValues{k,3}, ...
            'extrapolation', tableValues{k,4});
    end
    set_param([subsystem '/3_As'], 'Value', capacity);
    set_param([subsystem '/soc-ocv-15order_new2'], 'Expr', ocv);
    set_param([subsystem '/soc-ocv-15order_new3'], 'Expr', derivative);
    set_param([subsystem '/3_观测噪声1'], 'Value', measurementNoise);
    set_param([subsystem '/3_过程噪声1'], 'Value', processNoise);
    % All three gain charts already receive the same reference SOC input.
    % Switch only the chart feeding the PSO branch (third input) of the switch.
    switches = find_system(subsystem, 'SearchDepth', 1, 'BlockType', 'Switch');
    assert(numel(switches) == 1, 'Release:UnexpectedModelLayout', ...
        'Expected exactly one gain-selection switch.');
    switchPorts = get_param(switches{1}, 'PortHandles');
    oldLine = get_param(switchPorts.Inport(3), 'Line');
    if oldLine ~= -1, delete_line(oldLine); end
    chartPorts = get_param([subsystem '/' num2str(batteryNumber) '_Chart'], 'PortHandles');
    add_line(subsystem, chartPorts.Outport(1), switchPorts.Inport(3), 'autorouting', 'on');
    snapshot.gain_chart = [num2str(batteryNumber) '_Chart'];
end

function check_measurement(value, name)
    assert(isnumeric(value) && size(value,1) == 2 && size(value,2) > 1 && ...
        all(isfinite(value(:))) && value(1,1) == 0 && all(diff(value(1,:)) == 1), ...
        'Release:InvalidMeasurement', '%s must be finite 2-by-N data at one-second intervals.', name);
end

function close_owned_model(model)
    if bdIsLoaded(model), close_system(model, 0); end
end
