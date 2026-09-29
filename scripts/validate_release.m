function summary = validate_release()
%VALIDATE_RELEASE Check released model files and measurement pairs without simulation.
%   This function does not claim numerical reproduction of the published results.
    root = fileparts(fileparts(mfilename('fullpath')));
    modelNames = {'PSOmodel', 'EKFmodel', 'RCmodel'};
    for m = 1:numel(modelNames)
        assert(isfile(fullfile(root, 'src', 'models', [modelNames{m} '.slx'])), ...
            'Release:MissingModel', 'Missing model: %s.', modelNames{m});
    end
    cycles = {'HPPC', 'NEDC', 'FUDS'};
    expectedLastTime = [90718 23527 23033; 86607 22361 21689; 90697 23535 23031];
    batteryColumn = cell(9,1);
    cycleColumn = cell(9,1);
    sampleCount = zeros(9,1);
    lastTime = zeros(9,1);
    row = 0;
    for b = 1:3
        for c = 1:3
            row = row + 1;
            prefix = sprintf('%d_%s', b, cycles{c});
            current = load(fullfile(root, 'data', 'mat', [prefix '_I.mat']), 'i');
            voltage = load(fullfile(root, 'data', 'mat', [prefix '_V.mat']), 'v');
            assert(isfield(current, 'i') && isfield(voltage, 'v'), ...
                'Release:MissingVariable', 'Missing i or v in %s.', prefix);
            assert(isnumeric(current.i) && isnumeric(voltage.v) && ...
                size(current.i,1) == 2 && isequal(size(current.i), size(voltage.v)), ...
                'Release:UnexpectedDataShape', 'Expected matching 2-by-N data for %s.', prefix);
            assert(all(isfinite(current.i(:))) && all(isfinite(voltage.v(:))), ...
                'Release:NonfiniteData', 'Nonfinite measurement in %s.', prefix);
            assert(isequal(current.i(1,:), voltage.v(1,:)) && ...
                isequal(current.i(1,:), 0:expectedLastTime(b,c)), ...
                'Release:UnexpectedTimeAxis', 'Unexpected measurement timestamps for %s.', prefix);
            batteryColumn{row} = char(double('A') + b - 1);
            cycleColumn{row} = cycles{c};
            sampleCount(row) = size(current.i,2);
            lastTime(row) = current.i(1,end);
        end
        ocv = load(fullfile(root, 'data', 'mat', sprintf('%d_OCV_SOC.mat', b)));
        assert(isfield(ocv, 'ocv_x') && isfield(ocv, 'ocv_y') && ...
            numel(ocv.ocv_x) == numel(ocv.ocv_y) && ...
            all(isfinite(ocv.ocv_x(:))) && all(isfinite(ocv.ocv_y(:))), ...
            'Release:InvalidOCV', 'Invalid OCV/SOC measurement for battery %d.', b);
    end
    summary = table(batteryColumn, cycleColumn, sampleCount, lastTime, ...
        'VariableNames', {'battery', 'cycle', 'sample_count', 'last_time_s'});
    disp(summary);
    fprintf('Data integrity checks passed. No model simulation was performed.\n');
end
