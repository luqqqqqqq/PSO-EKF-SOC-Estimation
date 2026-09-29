# 快速开始

[返回项目首页](../README.md) · [文档导航](README.md)

## 直接使用数据与结果

下载仓库后，从 [数据说明](data.md)、[论文指标表](../results/tables/paper_metrics.csv) 和 [结果图](../results/figures/README.md) 开始。查看 CSV、PNG 和说明文档不需要 MATLAB。

## 运行模型

模型的保存版本为 **MATLAB R2023a**。仿真需要 MATLAB、Simulink 及模型中 Stateflow 图表所需的 Stateflow。其他版本的兼容性尚未验证。

在 MATLAB 中切换至仓库根目录：

```matlab
addpath('scripts');
validate_release();
result = run_experiment('B', 'NEDC', 'PSO');
plot(result.series.time_s, result.series.soc_reference_pct, '--');
hold on;
plot(result.series.time_s, result.series.soc_estimated_pct);
xlabel('Time (s)'); ylabel('SOC (%)');
legend('Reference', 'PSO gain');
```

`validate_release` 只检查数据和文件。`run_experiment` 默认仿真至最后一个测量时刻，保存时间序列和配置，不默认计算论文中的 MAE/MSE。

单组工况支持三种论文对比方法：

```matlab
baseline = run_experiment('B', 'NEDC', 'G1');
switchOff = run_experiment('B', 'NEDC', 'G0');
adaptive = run_experiment('B', 'NEDC', 'PSO');
```

如果 `PSOmodel` 已打开，请先自行保存并关闭。入口在内存中选择电池参数，结束后关闭其加载的模型，不保存对原模型的修改。

## 计算指定区间的指标

```matlab
result = run_experiment('B', 'NEDC', 'PSO', ...
    'MetricWindow', [7200 18000]);
disp(result.metrics);
```

以上区间是 API 使用示例，**不是经过确认的论文统计区间**。新结果位于 `build/results/` 下独立的运行目录，包含时间序列 CSV 与参数 JSON。不会覆盖 `results/` 中的论文报告值。

完整参数、批量实验和离线 PSO 搜索见 [复现说明](reproduction.md)。新增入口尚未在 MATLAB 中运行验证，使用前应先运行一组实验并核对输出。
