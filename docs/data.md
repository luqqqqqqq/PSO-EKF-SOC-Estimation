# 实验数据

[返回项目首页](../README.md) · [文档导航](README.md)

数据对应 [正式论文](https://doi.org/10.1016/j.egyr.2025.07.023) 的最终实验输入。实验温度为 25 °C，电流和端电压的采样间隔为 1 s。提供的数据已经是模型使用的数值输入。

## 电池和工况

| 电池 | MAT 前缀 | 论文标称容量 | HPPC 采样数 | FUDS 采样数 | NEDC 采样数 |
| --- | --- | --- | --- | --- | --- |
| A | `1_` | 27 Ah | 90,719 | 23,034 | 23,528 |
| B | `2_` | 25 Ah | 86,608 | 21,690 | 22,362 |
| C | `3_` | 27 Ah | 90,698 | 23,032 | 23,536 |

A 与 C 在论文中为同型号、不同生产批次。标称容量与模型中标定的库仑计数容量是不同参数，请保留模型各自的容量设置。

HPPC 用于模型参数辨识和验证；FUDS、NEDC 为动态工况。每组时间从 0 s 开始，最后时刻等于采样数减 1。机器可读索引见 [datasets.csv](../data/datasets.csv)。

## CSV 字段

`data/csv/A_HPPC.csv` 等九个文件，每行一个采样点：

| 字段 | 单位 | 含义 |
| --- | --- | --- |
| `time_s` | s | 相对采样时间 |
| `current_A` | A | 测量电流，**放电为负、充电为正** |
| `voltage_V` | V | 测量端电压 |

模型已有电流方向转换，导入时不要再对电流取反。CSV 未新增或插值 SOC 真值列。

`A_OCV_SOC.csv`、`B_OCV_SOC.csv`、`C_OCV_SOC.csv`：

| 字段 | 单位 | 含义 |
| --- | --- | --- |
| `soc_fraction` | 1 | SOC 分数，1 对应 100% |
| `ocv_V` | V | 开路电压 |

三组 OCV–SOC 点数分别为 23、22、23。保留原有顺序和数值；零附近约 10⁻¹⁵ 的浮点残差也原样保留。

## MAT 字段

| 文件 | 变量 | 排列 |
| --- | --- | --- |
| `{1,2,3}_{HPPC,FUDS,NEDC}_I.mat` | `i` | `2 × N`，第一行为时间，第二行为电流 |
| `{1,2,3}_{HPPC,FUDS,NEDC}_V.mat` | `v` | `2 × N`，第一行为时间，第二行为端电压 |
| `{1,2,3}_OCV_SOC.mat` | `ocv_x`、`ocv_y` | SOC 分数和 OCV，均为行向量 |

MAT 与 CSV 数值逐项一致。MAT 文件头的生成描述已规范化，不改变数组。数据中没有 NaN、Inf、重复时间或缺失的 1 s 时间点。

## 导入示例

MATLAB：

```matlab
T = readtable(fullfile('data', 'csv', 'B_NEDC.csv'));
plot(T.time_s, T.voltage_V);
xlabel('Time (s)'); ylabel('Terminal voltage (V)');
```

Python 标准库：

```python
import csv
from pathlib import Path

with Path('data/csv/B_NEDC.csv').open(newline='', encoding='utf-8') as f:
    samples = list(csv.DictReader(f))
```

结果表的 MAE 以 SOC 百分点表示，MSE 以百分点评方表示；结果图片沿用论文中的 `Error (%)` 标签。详见 [实验结果](results.md)。
