function results = run_all()
%RUN_ALL Run all 27 stored battery/cycle/method combinations.
%   Every run ends at the last measurement timestamp. No aggregate error
%   metrics are calculated because no paper evaluation windows are assumed.
%   Use run_experiment with MetricWindow to request a specific evaluation.
%   This entry point has been statically checked, not executed in MATLAB.
    batteries = {'A', 'B', 'C'};
    cycles = {'HPPC', 'NEDC', 'FUDS'};
    methods = {'G1', 'G0', 'PSO'};
    results = cell(3, 3, 3);
    for b = 1:3
        for c = 1:3
            for m = 1:3
                results{b,c,m} = run_experiment(batteries{b}, cycles{c}, methods{m});
            end
        end
    end
end
