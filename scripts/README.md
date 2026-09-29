# MATLAB entry points

Use MATLAB R2023a with Simulink and Stateflow. Add this folder to the MATLAB path, or make it the current folder. The supplied models were saved in R2023a. The new entry points have been statically reviewed but have not been run in MATLAB as part of this release.

## Check the release

```matlab
summary = validate_release();
```

This checks the three model files, nine current/voltage measurement pairs, their timestamps and finite values, and three OCV/SOC datasets. It does not simulate a model or validate agreement with the paper.

## Run one case

```matlab
result = run_experiment('C', 'NEDC', 'PSO');
```

| Argument | Values | Meaning |
|---|---|---|
| Battery | `A`, `B`, `C` | Selects the corresponding stored parameter group in `PSOmodel` |
| Cycle | `HPPC`, `NEDC`, `FUDS` | Selects its measured current and voltage |
| Method | `G1`, `G0`, `PSO`, `FIXED` | Selects the correction-gain method |

`G1` supplies gain 1. `G0` supplies gain 0 in the original model's plateau interval (0.05 < SOC < 0.95), with gain 1 outside that interval. `FIXED` uses a caller-supplied gain with the same gating. `PSO` uses the stored offline gain schedule for the selected battery; it does not perform a new optimization.

The original model schedules these gains using its coulomb-counted reference SOC. The runner preserves that model connection, the original noise blocks, initial states, lookup settings and measured-current sign convention (discharge is negative).

| Name-value option | Default | Meaning |
|---|---|---|
| `StopTime` | Last measurement timestamp | Simulation endpoint in seconds, no later than the input data ends |
| `MetricWindow` | `[]` | Inclusive `[start_s end_s]` interval; empty means no metrics are calculated |
| `FixedGain` | `1` | Nonnegative scalar used by `FIXED` |
| `WriteResults` | `true` | Whether to write CSV and JSON files |
| `OutputDir` | `build/results` in the repository | Parent directory for a new, separate run folder |

For a short initial run:

```matlab
result = run_experiment('C', 'NEDC', 'PSO', 'StopTime', 100);
```

For explicitly selected evaluation and optimization windows:

```matlab
% Illustrative interval only; this is not a certified paper evaluation window.
result = run_experiment('B', 'HPPC', 'PSO', ...
    'MetricWindow', [21600 79200]);

candidate = run_experiment('B', 'HPPC', 'FIXED', ...
    'FixedGain', 0.1, 'StopTime', 79200, ...
    'MetricWindow', [21600 79200], 'WriteResults', false);
objective = candidate.metrics.max_abs_error_pp;
```

The returned structure contains:

- `series`: a table with `time_s`, `soc_reference_pct`, `soc_estimated_pct`, and `soc_error_pp`.
- `metrics`: an empty structure when no window is requested; otherwise `mae_pp`, `mse_pp2`, `rmse_pp`, `max_abs_error_pp`, the requested window, the first/last included sample and sample count.
- `parameters`: a snapshot of the selected model parameter expressions, tables and gain-chart identity.
- `csv_file` and `metadata_file`: output paths, or empty strings when `WriteResults` is false.

SOC error is estimated SOC minus reference SOC, measured in percentage points. MSE is therefore in squared percentage points. Each written run has a separate directory, so earlier runs are preserved. The JSON records the method, stop time, requested statistical interval, MATLAB release and parameter snapshot.

## Run all standard combinations

```matlab
results = run_all();
```

This runs 27 combinations: three batteries × three cycles × `G1`/`G0`/`PSO`. Every simulation ends at the last measurement timestamp. It returns a `3×3×3` cell array ordered by batteries `{A,B,C}`, cycles `{HPPC,NEDC,FUDS}`, and methods `{G1,G0,PSO}`. No aggregate metrics are calculated because an evaluation interval is not assumed. Full runs can take substantial time.

## Model handling and result interpretation

The entry point runs `PSOmodel` for all methods so each comparison uses that model's own parameter groups. `EKFmodel` and `RCmodel` are separate supplied models; their embedded parameters are not substituted into this runner.

`PSOmodel` must be closed before running the entry point. If a model with that name is already loaded, the entry point stops so any unsaved work remains intact. It loads the release model, changes the selected parameters and input files in memory, and closes only that model without saving. It supplies `G` and `PSO` through `Simulink.SimulationInput`; it does not change the MATLAB base workspace. Generated simulation caches are directed to `build`.

The newly generated CSV files are reruns with the selected stored parameters and explicit settings. Agreement with published figures or statistics requires the same experimental configuration and evaluation interval; these entry points do not certify that agreement. Consult the repository's published-result files separately.
