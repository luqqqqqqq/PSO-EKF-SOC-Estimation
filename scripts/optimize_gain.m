function search = optimize_gain(battery, window, varargin)
%OPTIMIZE_GAIN Repeat an offline PSO search for one HPPC time interval.
%   search = optimize_gain('B', [27361 31321], 'Seed', 0)
% The example window is illustrative, not a certified paper evaluation window.
% This utility searches a constant plateau gain using maximum absolute SOC
% error on the specified inclusive interval. It does not overwrite the final
% gain schedules stored in PSOmodel. A new search is not a reconstruction of
% the original stochastic optimization trials.
%
% Each fitness evaluation runs the released model from time zero. This is an
% offline and potentially slow calculation. MATLAB/Simulink/Stateflow are
% required; this entry point has received static checks only.

    battery = validatestring(battery, {'A', 'B', 'C'});
    validateattributes(window, {'numeric'}, ...
        {'real', 'finite', 'vector', 'numel', 2, 'nonnegative'});
    assert(window(2) > window(1), 'Release:InvalidWindow', ...
        'The end of the interval must be greater than its start.');
    parser = inputParser;
    parser.addParameter('Seed', 0, @(x) isnumeric(x) && isscalar(x) && ...
        isfinite(x) && x >= 0 && x <= 2^32-1 && fix(x) == x);
    parser.addParameter('Particles', 2, @(x) isnumeric(x) && isscalar(x) && ...
        isfinite(x) && x >= 2 && fix(x) == x);
    parser.addParameter('Iterations', 50, @(x) isnumeric(x) && isscalar(x) && ...
        isfinite(x) && x >= 1 && fix(x) == x);
    parser.parse(varargin{:});
    settings = parser.Results;

    previousRandomState = rng;
    restoreRandomState = onCleanup(@() rng(previousRandomState)); %#ok<NASGU>
    rng(settings.Seed, 'twister');
    count = settings.Particles;
    position = rand(1, count);
    velocity = (-0.5 + rand(1, count)) / 100;
    personalPosition = position;
    personalError = inf(1, count);
    bestGain = NaN;
    bestError = inf;
    history = zeros(settings.Iterations, 3);
    inertia = 0.6;
    cognitive = 0.1;
    social = 0.1;

    for iteration = 1:settings.Iterations
        for particle = 1:count
            run = run_experiment(battery, 'HPPC', 'FIXED', ...
                'FixedGain', position(particle), 'MetricWindow', window, ...
                'StopTime', window(2), 'WriteResults', false);
            error = run.metrics.max_abs_error_pp;
            if error < personalError(particle)
                personalError(particle) = error;
                personalPosition(particle) = position(particle);
            end
        end
        [candidateError, index] = min(personalError);
        if candidateError < bestError
            bestError = candidateError;
            bestGain = personalPosition(index);
        end
        history(iteration, :) = [iteration, bestGain, bestError];
        for particle = 1:count
            velocity(particle) = inertia * velocity(particle) ...
                + cognitive * rand() * (personalPosition(particle) - position(particle)) ...
                + social * rand() * (bestGain - position(particle));
            position(particle) = min(1, max(0, position(particle) + velocity(particle)));
        end
    end
    search = struct('battery', battery, 'cycle', 'HPPC', ...
        'window_s', window(:)', 'best_gain', bestGain, ...
        'max_abs_error_pp', bestError, 'seed', settings.Seed, ...
        'particles', count, 'iterations', settings.Iterations, ...
        'inertia', inertia, 'cognitive', cognitive, 'social', social, ...
        'gain_bounds', [0 1], ...
        'history', array2table(history, 'VariableNames', ...
        {'iteration', 'best_gain', 'max_abs_error_pp'}));
end
