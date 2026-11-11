---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f3d7249bacac4923999ceda47b8083c_e92087c0d2f211f196c5525400248c00
    ReservedCode1: cFJYBF6rTIVlHPdOQL9UONNQiQh4/Uuh///+oKsSxc2TAH+LIb3Gj2qc1G6favRJBr3w9eWtzZMmzhFuoEV9ATlePGocg8fjPme33BxWM9OXmPd+HXIhP+ydHNlBZ20Zw34ZWaX4AEZhDeaEuuhmpeQ0EvLLcOLpncD/Kgnpls4ZRlCAb680INxHlP8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f3d7249bacac4923999ceda47b8083c_e92087c0d2f211f196c5525400248c00
    ReservedCode2: cFJYBF6rTIVlHPdOQL9UONNQiQh4/Uuh///+oKsSxc2TAH+LIb3Gj2qc1G6favRJBr3w9eWtzZMmzhFuoEV9ATlePGocg8fjPme33BxWM9OXmPd+HXIhP+ydHNlBZ20Zw34ZWaX4AEZhDeaEuuhmpeQ0EvLLcOLpncD/Kgnpls4ZRlCAb680INxHlP8=
---

# 标注集扩充评估方案（v2 · 数字全部实测复核版）

> 生成日期：2026-10-29
> 适用代码基线：`main` @ a4aac8c；artifact `data/trade_classifier.joblib`（built_at 2026-10-27 19:48，sklearn 1.5.2 / python 3.12.3）
> 复核原则：本文件出现的每个数字均标注来源文件或计算方式，见附录 A。上一版（2026-10-28）中 test top-1 77.1%、"tiling→flooring 10 例"、"painting↔drywall 混淆"等结论与仓库实测不符，已全部作废重算。
> **v3 执行记录（2026-10-29）**：§3.4 四项前置全部落地——线上回流核验（`reports/online_backflow_baseline.md`）、`CATEGORY_MAP` 修正、artifact 归档、评测产物绑定哈希。artifact 已按修正后的 `CATEGORY_MAP` 重建（sha256 `f12ab8d0abb8…`），§1.3/§1.4 数字随之下调口径；同时修掉一处评测器缺陷（`eval_trade_test.py` / `eval_holdout.py` 会静默复用出厂 classifier，而该分类器的训练集含被评样本，导致报告出过 100% 的假成绩）。逐项见新增 §0。

---

## 0. v3 执行记录（2026-10-29，方案前置项的落地结果）

本节不改变 §1–§6 的结论方向，只登记"已经改了哪些代码、数据因此变成什么样"，以及一处必须写进实验记录的评测器缺陷。

### 0.1 修掉的问题

| # | 问题 | 处置 | 证据 |
|---:|---|---|---|
| 1 | `CATEGORY_MAP` 把三个地板工种（`Carpet Installers` / `Floor Layers, Except Carpet, Wood, and Hardwood` / `Floor Sanders and Finishers`）同时映射到 `tiling`，制造 25 行"伪双标签"——次标签从不落地，却让 §2.4 的双标签统计失真 | `scripts/build_trade_matcher.py` 中 `tiling` 只保留 `Tile and Stone Setters`；`drywall` 同时去掉 `Insulation Workers` 的越界映射 | `tiling` 标题数 25 → 7，`drywall` 30 → 23，训练集多标签行数归零 |
| 2 | 旧 artifact 无归档、无哈希 | `data/archive/trade_models_v0_20261027/` 存 v0 三件套 + `SHA256SUMS.txt` + `README.md`（注明其来自 `CATEGORY_MAP` 未修版、含 25 行伪双标签） | `classifier b13dcf7f… / matcher 8785670d… / profiles 750168fc…` |
| 3 | 评测产物与 artifact 版本脱钩（§1.3 附带发现） | 三个评测脚本的预测 CSV 改为 `*_predictions_<sha12>.csv`；报告内联写出 artifact sha256 与 CSV 文件名 | `reports/trade_matcher_valid_predictions_f12ab8d0abb8.csv` 等 |
| 4 | `verify_production_artifact.py` 把"应该等于 96.4%/94.0%"硬编码在源码里，模型一换就只能靠人记 | 期望值下沉到 `reports/trade_model_baseline.json`，与 artifact sha256、CSV 哈希一并登记；校验时先比哈希再比数字，`--record` 用于有意重训后重登记 | `reports/trade_model_baseline.json` |
| 5 | `eval_trade_test.py` / `eval_holdout.py` **静默复用出厂 classifier**（训练集包含 test 行本身） | 两个脚本在评分阶段把 classifier 层显式关闭（`ai._TRADE_CLASSIFIER = False`），报告改为声明"本页只测关键词+质心 matcher" | 见 0.3 前后对比 |

### 0.2 重建后的生产 artifact

| 项 | v2 文档口径 | 现在（`main` 工作区） |
|---|---|---|
| `samples` | 4591 | **4566**（`tiling` 少 18 行、`drywall` 少 7 行样本） |
| `synthetic_rows` | 3074 | 3074（未变） |
| `classes` / `C` / `label_mode` | 16 / 4.0 / single | 16 / 4.0 / single |
| 文件大小 | 2.95 MB | 2.82 MB |
| sha256 | 未登记 | `f12ab8d0abb82afa6b8cea777a836218971bf8cc23ceaff61365136d2222d2cf` |

### 0.3 修正映射 + 关闭泄漏后的实测（`scripts/eval_trade_validation.py`，2026-10-29 重跑）

| 集 | 阶段 | n | 准确率 | 与前一阶段比较（McNemar） |
|---|---|---:|---:|---|
| dev | 关键词 matcher（before） | 104 | 100.0% | — |
| dev | + 分类器（final） | 104 | 96.2% | fixed 0 / broken 4，p=0.125（分类器在 dev 上无增益，属已知饱和） |
| test | 关键词 matcher（before） | 83 | 79.5%（66/83） | — |
| test | + 分类器（final） | 83 | **92.8%（77/83）** | fixed 11 / broken 1，p=0.0063 |
| valid | 关键词 matcher（before） | 83 | 71.1% | — |
| valid | + 分类器（final） | 83 | **95.2%（79/83）** | fixed 21 / broken 1，p=1.1e-05 |

关键词层单独评测（`scripts/eval_trade_test.py`，泄漏关闭后重跑）：`dev 78.8%（82/104）→ 99.0%（103/104）`、`test 79.5%（66/83）→ 84.3%（70/83）`；McNemar `dev p=5.7e-06`、`test p=0.289`（fixed 6 / broken 2）。

**读数纪律**：`test` 的 92.8% 与 `valid` 的 95.2% 都是"分类器 + 已读过的集"，只能作为回归守护值，不能当作泛化证明；§2.1 的 Wilson 区间结论不变。

### 0.4 线上与仓库已对齐（2026-10-29 19:0x 实测 `/health`）

Render 已随本次推送重建（artifact `built_at 2026-10-29 18:43`，python 3.12.3 / sklearn 1.5.2）：

| 线上读到的字段 | 值 | 与本地 artifact 是否一致 |
|---|---|---|
| `trade_classifier.samples` | 4566 | 一致 |
| `label_mode` / `C` / `synthetic_rows` | single / 4.0 / 3074 | 一致 |
| `trade_matcher.profiles.tiling` / `drywall` | 7 / 23 | 一致（修正后） |
| `models_ok` / `degraded` / `version_mismatch` | true / [] / [] | 通过 |

即：线上服务已在跑修正映射后的模型，不存在"仓库修好、线上还是旧版"的错位。

### 0.5 仍然开着的

1. ~~线上回流核验~~ **已完成**：`reports/online_backflow_baseline.md` 记录了 Supabase 实查结果——`tasks` 4 行（其中仅 2 行有 `trade`）、`workers` 6 行、`prediction_history` 2 行、`ai_decision_log` **0 行**。可用训练文本 ≈ 0，线上不会自己长出数据。
2. ~~`ai_decision_log` 建表~~ **不需要做**：线上表与索引均已存在（`log_id / task_id / was_overridden / (project_id, created_at, stage)`）。剩下的疑点是"创建任务的分支不写决策日志"，属产品口径确认，不是建表。
3. §4–§6 的标注规范、样本量、验收门槛均未变动，仍按 v2 执行。

## 1. 现有标注集与评测基线

### 1.1 数据漏斗（`data/job_categorization.parquet`，经 `scripts/eval_holdout.py::load_labelled_frame()`）

| 环节 | 数量 | 说明 |
|---|---|---|
| 原始行 | 6,539 | 字段仅 `title` / `category` 两列 |
| 原始类目数 | 864 | 含军人、运动员等非施工类 |
| 映射到的类目 | 67（7.8%） | → 16 个 canonical 工种 |
| 入选标注行 | 518（7.9%） | 未映射 6,021 行 |
| 去重标题 | 517 | 清洗后唯一（1 条标题重复） |
| 双标签行 | 25（4.8%） | flooring+tiling 18、drywall+insulation 7 |
| 三套切分 | dev 104 / test 83 / valid 83 | seed 42 / 2026 / 31337（链式切分） |
| 训练留存 | 248 | 518 − 104 − 83 − 83 |

平均每类 32 行实例、最短类 12 行。16 类线性判别任务下，这个密度不足以约束类间边界。

### 1.2 类别分布（全量 518 行，按工时实例计数）

| 工种 | 全量 | 工种 | 全量 |
|---|---|---|---|
| equipment | 86 | tiling | 25 |
| electrical | 58 | carpenter | 25 |
| laborer | 51 | insulation | 21 |
| welding | 47 | flooring | 18 |
| masonry | 43 | hvac | 17 |
| supervision | 39 | roofing | 13 |
| painting | 32 | glazing | 12 |
| drywall | 30 | plumbing | 26 |

最长/最短 = 86/12 = **7.2 倍**。合成语料未纠偏：3,074 行训练侧合成数据中 equipment 512、glazing 92，仍为 **5.6 倍**（`reports/synthetic_trade_stats.json`）。

### 1.3 已发布指标与可用边界（关键修正）

| 评测集 | n | 结果 | 95% CI | 现在还能不能用 |
|---|---|---|---|---|
| dev（seed 42） | 104 | 100.0%（104/104） | — | **不能**。关键词表就是照它的失败改的，属训练内评估 |
| test（seed 2026） | 83 | 84.3%（70/83）<br>调参前 79.5%（66/83） | 75.0–90.6% | **不能**。已用于一次性前后对比，独立性已消耗 |
| valid（seed 31337，F 配置） | 83 | 96.4%（80/83） | 89.9–98.8% | **不能**。F 配置正是从该集选出的，属事后乐观口径 |
| valid 同集·V0 基线 | 83 | 92.8%（77/83） | 85.1–96.6% | 同上，仅作口径参照（v3 重测：关键词层 71.1% → 全链 95.2%） |
| holdout（seed 42，80/20） | 104 | 100.0%（104/104） | — | **不能**。与 dev 同一批样本，模型已见过全部标题 |

**结论**：仓库内四套评测集全部已被读取或用于决策，任何新"提升"都无法在其中取得无偏证明。这是本次扩充的第一动因。

**附带发现（需记入实验记录）**：`reports/trade_matcher_valid_predictions.csv`（写于 10-27 15:49）反映的是 89.2%（74/83）的旧 artifact，而最终 artifact 于 19:48 重建、对应 96.4%。**预测 CSV 与 artifact 版本已脱钩**——该问题已在 v3 修复（CSV 文件名带 artifact 短哈希，§0.1 #3/#4）：同名文件在不同时间指向不同模型，是复现性隐患（见 6.3 纪律第 5 条）。

### 1.4 生产模型现状（`joblib.load` 实读 meta）

算法 `tfidf(word 1-2 + char_wb 3-5) + LogisticRegression`；`samples=4566`（v3 重建；构成 = 517 个去重 (标题, 工种) 对 + 975 种子行 + 3,074 合成行；旧值 4591 的构成是 542 + 975 + 3,074，减少的 25 行正是 `tiling`/`drywall` 的重复对）；`C=4.0`；`label_mode=single`；`classes` 16 个；决策阈值 `threshold=0.35`、`margin=0.25`；训练时间 2026-10-27 19:47。

### 1.5 线上回流现状（不能沿用旧判断）

本地 SQLite 快照 `construction_management.db`：`tasks` 0、`workers` 0、`prediction_history` 0 行，且**无 `ai_decision_log` 表**（该表只在 Postgres 迁移路径创建）。

生产 Supabase 已于 2026-10-29 实查（见 `reports/online_backflow_baseline.md`）：`tasks` 4、`workers` 6、`prediction_history` 2、`ai_decision_log` 0；`tasks` 里只有 2 行带 `trade`（`plumbing` / `electrical`，均为冒烟文本）。

因此事实是：**本地与线上都没有可用于训练的业务标注，线上回流规模约等于 0**。扩充不能假设"线上数据会自然积累"，必须按人工标注 + 受控合成推进（原前置项已注销，见 §0.4）。

---

## 2. 瓶颈诊断（五条，全部实测）

### 2.1 瓶颈一：n=83 使所有结论落在宽区间内

| 观测（test） | n | 观测值 | Wilson 95% CI | 区间半宽 |
|---|---|---|---|---|
| 整体 top-1 | 83 | 84.3% | 75.0–90.6% | ±7.8pp |
| drywall 召回 | 5 | 20.0% | 3.6–62.4% | ±29.4pp |
| painting 召回 | 4 | 25.0% | 4.6–69.9% | ±32.6pp |
| glazing / hvac / roofing 召回 | 1 | 100% | 20.7–100% | ±39.7pp |

单类 n=1~5 时区间宽 59–79 个百分点：**"painting 召回 25%"与"painting 召回 70%"在统计上不可区分**。逐类召回驱动的调优，在现有样本量下没有判据。

### 2.2 瓶颈二：McNemar 效力不足，真实改善被判不显著

test 上关键词扩充前后实测：修复 6 行、破坏 1 行，不一致 7 行（8.4%），McNemar 精确检验 **p=0.125**。以该效应（不一致率 0.084、正向占比 0.857）做 4,000 次精确二项模拟：

| n | 检出效力（α=0.05） |
|---|---|
| 83（现状） | **0.33** |
| 120 | 0.53 |
| 150 | 0.67 |
| 200 | **0.83** |
| 270 | 0.93 |
| 620（本方案冻结集） | 1.00 |

n=83 时即使真实提升存在，也只有约 1/3 概率被检出。要把效力提到 0.80，需 **n≈200** 配对样本；这也是"74.7%→80.7%（+6.0pp）"只能记为 p=0.125 的原因——不是效果不存在，是样本不够。

### 2.3 瓶颈三：真实错误结构（推翻旧结论）

按 `*_predictions.csv` 的 `expected_primary → predicted_primary` 实算：

**test（16 个错误）**

| 错误对 | 次数 | 性质 |
|---|---|---|
| drywall → masonry | 3 | 上位/相邻工序（砌筑-隔墙同工序段） |
| welding → equipment | 2 | 钢构焊接与设备安装共用机具词 |
| laborer → insulation | 2 | 辅助工与保温工工作面重叠 |
| painting → glazing / tiling / equipment | 1 / 1 / 1 | 分散，非稳定单对 |
| drywall → roofing | 1 | "板材/吊顶"语义簇 |
| insulation → glazing | 1 | 围护结构工序相邻 |
| welding → masonry | 1 | — |
| (skip) 拒答 | 3 | supervision 2、plumbing 1 |

**valid 快照（9 个错误，旧 artifact）**

| 错误对 | 次数 |
|---|---|
| laborer → (skip) / plumbing → (skip) | 2 / 2 |
| equipment / electrical → (skip) | 1 / 1 |
| insulation → hvac、roofing → equipment、tiling → carpenter | 各 1 |

三条必须写进方案的更正：

1. **"tiling→flooring 系统性混淆（10 例）"不成立**：270 行评测池中该错误 **0 例**。tiling 在 test 3 行全对、在 valid 2 行错 1（→carpenter）。旧结论误把"双标签行预测为 flooring"当成错误——那 6 行实际是 `correct=True`（见 2.4）。
2. **"painting↔drywall 互误"不成立**：painting 的错误全部发散到 glazing/tiling/equipment；drywall 的错误集中到 masonry（3）。painting 的真实问题是样本太少（test 4 行、valid 4 行），两个 4 行样本给出 25% 与 100% 两种结论，本质是抽样波动。
3. **拒答是最大单一错误源**：test 16 个错误中 3 个（19%）、valid 快照 9 个错误中 6 个（67%）来自 `(skip)`。`threshold=0.35 / margin=0.25` 对短文本过于保守，把本可判的样本推给了兜底。

### 2.4 瓶颈四：双标签不是"被压成单标签"，而是"次标签从不落地"

实测（`*_predictions.csv`）：dev 6 行 / test 4 行 / valid 2 行为双标签样本，而**多标签输出在全部 270 行中只出现 1 次**（dev 的 `hvac;welding`）。逐行看这 12 行：

| 文本 | 期望 | 预测 | 结果 |
|---|---|---|---|
| commercial carpet installer | tiling;flooring | flooring | ✅ |
| composition floor layer | tiling;flooring | flooring | ✅ |
| floor finisher | tiling;flooring | flooring | ✅ |
| residential carpet installer | tiling;flooring | flooring | ✅ |
| wall to wall carpet installer | tiling;flooring | carpenter | ❌ |
| carpet layer / cork / laminate / vinyl / floor sander / floor scraper | tiling;flooring | flooring | ✅ 全对 |
| composition weatherboard installer | drywall;insulation | roofing | ❌ |

成因在**标签映射**而非模型：`build_trade_matcher.py` 的 `CATEGORY_MAP` 把 `Carpet Installers`、`Floor Layers, Except Carpet, Wood, and Hard Tiles`、`Floor Sanders and Finishers` 同时映射到 `tiling` 与 `flooring`，于是这 18 行天然双标签；但这些标题里没有任何贴砖语义词，模型只会输出 flooring。**结果不是判错，而是 tiling 侧永远缺失**——派工时次工种拿不到。

据此排序，双标签工作的第一优先级不是"改模型"，而是：① 修正 `CATEGORY_MAP` 中地毯/地板类目对 tiling 的误覆盖（保留 flooring 单标）；② 双标签只对**真实共现**（如 drywall+insulation）保留；③ 才对次标签落地做预测侧改造。

### 2.5 瓶颈五：映射覆盖与文本域双重错配

| 问题 | 证据 | 影响 |
|---|---|---|
| 映射覆盖率低 | 67/864 类目（7.8%），6,021 行未映射 | 长尾类无扩充来源 |
| 映射粒度不一致 | `Carpet Installers` 同时进 tiling 与 flooring（2.4 节）；"Painters" 混入工业喷漆 | 类目级标签自带 ±1 类噪声，25 行双标签全是此类伪重叠 |
| 文本域不匹配 | 语料为 O*NET 职位名/描述，线上输入是现场口语 | dev 100% vs test 80.7%，-19.3pp 即泛化落差 |
| 结构缺失 | **flooring 在 test / valid 均 0 行**（其 18 行全在 dev 与训练侧） | flooring 从未在"未触碰集"上被度量过 |
| 合成不纠偏 | equipment 512 / glazing 92（5.6 倍） | 头部类被进一步强化 |

### 2.6 诊断结论（按投入产出比排序）

1. **评测可信度**：新建 620 行冻结集，补 flooring 等结构性缺失类；
2. **标签映射修正**：`CATEGORY_MAP` 去伪共现（影响 25 行 = 4.8% 标签）；
3. **短板类样本**：glazing 12 / roofing 13 / hvac 17 / flooring 18 / insulation 21 / tiling 25 / painting 32；
4. **拒答阈值重标定**：用扩充后的集回归 `threshold / margin`，不再用 83 行调；
5. **次标签落地**：在前四项完成后才做。

---

## 3. 扩充目标与分批采样

### 3.1 量化目标

| 编号 | 目标 | 现状（实测） | 目标值 | 依据 |
|---|---|---|---|---|
| O1 | 冻结评测集 | 0 套可用 | **620 行**（16 类×35 + 双标签 60），哈希加锁、一次性 | 逐类 ±10pp、整体 ±3.1pp（5.1） |
| O2 | 训练侧最短类 | glazing 12 / roofing 13 / hvac 17 / flooring 18 | **每类 ≥80** | 16 类线性分类器最低密度；最长类 86 可正常收敛 |
| O3 | 标签映射噪声 | 25 行双标签中 18 行为伪共现 | 伪共现清零；真实共现白名单 ≤5 对 | 2.4 节 |
| O4 | 冻结集 top-1 | 80.7%（test）/ 96.4%（valid，乐观） | **≥90%**，CI 下限 ≥87% | 取两集之间偏上 |
| O5 | 宏召回 / 最短类召回 | test：drywall 20%、painting 25%、laborer 66.7% | 宏召回 **≥85%**；glazing/roofing/hvac **≥75%** | 长尾不达标则线上必错派 |
| O6 | 统计效力 | 0.33（n=83） | **≥0.80**（n≥200） | 2.2 节模拟 |

### 3.2 分批采样

来源优先级：① 现场工单文本（需业务侧导出）→ ② 施工班组/工长访谈转写 → ③ O*NET 未映射邻域类目（Ceiling Tile、Terrazzo 等，按边界规则筛）→ ④ 受控合成（只扩写措辞，不加类先验）。

| 批次 | 内容 | 行数 | 构成 | 起止 | 验收 |
|---|---|---|---|---|---|
| B0 试点 | 校准手册 | 152 | 16 类×8 + 双标签 24 | 11-03→11-07 | 双人 κ≥0.75；争议率 ≤15% |
| B1 短板类 | 补最短 7 类 | 420 | glazing/roofing/hvac/flooring/insulation/painting/tiling 各 60 | 11-10→11-21 | 各类累计 ≥80；类内 κ≥0.75 |
| B2 主体类 | 头部 9 类措辞多样性 | 540 | 各 60，其中 ≥30% 为现场口语改写 | 11-10→11-21 | 与 518 行去重后重复率 ≤5% |
| B3 双标签 | 真实共现 | 260 | drywall+insulation 120、tiling+flooring（真贴砖）60、carpenter+flooring 40、electrical+equipment 40 | 11-17→11-28 | 每条填双判据字段（4.3） |
| B4 冻结集 | 620 行盲测集 | 620 | 16 类×35 + 双标签 60，与训练侧文本哈希互斥 | 11-24→11-28 | 哈希落盘、只读 |
| 合计 | — | **1,992** | 训练侧 1,372 + 评测 620 | 11-03→11-28 | — |

放量规则：B0 不达标不放量；B1/B2 任一批争议率 >20% 即暂停；B4 与训练侧物理隔离（`reports/frozen_eval_manifest.json`）；每批交付 `data/annotations/batch_<Bx>.jsonl` + `reports/batch_<Bx>_qa.md`。

### 3.3 与既有合成语料的关系

现有 3,074 行合成数据保留在训练侧（`synthetic_trade_tasks.jsonl`），但**上限 40% 占比、且不得进入冻结集**。它的价值是措辞多样性，不是类先验——5.6 倍的类间比例已证明它会放大头部类。

### 3.4 开工前置（必须先做，否则本方案无验收基础）

1. **线上回流核验（已完成 2026-10-29）**：结果见 `reports/online_backflow_baseline.md`（`tasks` 4 / `workers` 6 / `prediction_history` 2 / `ai_decision_log` 0）。结论：可用真实文本 ≈ 0，B1–B3 不依赖线上导出；原"若 >0 则优先取真实文本"的前提不成立（价值远高于访谈转写）。
2. **`CATEGORY_MAP` 修正（已完成 2026-10-29）**：`tiling` 只留 `Tile and Stone Setters`，`drywall` 去掉 `Insulation Workers`；`tiling` 标题 25 → 7、`drywall` 30 → 23，多标签行归零，dev/test/valid 重跑见 §0.3。
3. **artifact 归档（已完成）**：v0 三件套存于 `data/archive/trade_models_v0_20261027/`（含 `SHA256SUMS.txt` 与 `README.md`）；新 artifact sha256 `f12ab8d0…` 登记在 `reports/trade_model_baseline.json`。
4. **评测产物绑定版本（已完成）**：`reports/*_predictions_<sha12>.csv`，报告内联写出同一哈希，见 §0.1 #3。

---

## 4. 标注规范草案

### 4.1 标注单元与落盘格式

一条工单/工序文本 = 一条样本；一条文本含多个独立工序时拆分并保留 `parent_id`。

```json
{"id":"B1-0042","text":"卫生间墙面贴砖，含地面找平","trades":["tiling"],"primary":"tiling",
 "secondary":[],"uncertain":false,"skip_reason":null,
 "judge_fields":{"explicit_trade_word":true,"process_verb":"贴砖","material":"瓷砖"},
 "annotator":"A03","reviewer":"R01","batch":"B1","source":"site_order","ts":"2026-11-12T10:20:00"}
```

### 4.2 单标签主标签判定顺序（不得跳级）

| 优先级 | 判据 | 示例 |
|---|---|---|
| 1 | 明确工种名词 | "瓦工""油工""焊工" |
| 2 | 工序动词 + 施工对象 | "贴地面砖"→tiling；"刷乳胶漆"→painting |
| 3 | 专属机具 + 典型作业 | "开槽机布管"→electrical（切割机、搅拌机不具排他性） |
| 4 | 材料名 | "瓷砖胶""岩棉"——**仅作佐证**，不得单独定类 |
| 5 | 全部缺失 | 判 `(skip)`（4.5 L2） |

### 4.3 双标签五条件（全部满足才可双标）

1. 主体独立：两工序由不同工种工人独立承担；
2. 同一工单/工作面/时间段；
3. 工作量各 ≥20%；
4. 无隶属关系：laborer 辅助任何工种一律单标 laborer；supervision 仅在文本主体为"验收/巡检"时单标；
5. 有双判据：两工种各至少 1 条来自 4.2 优先级 1–3。

| 文本 | 判定 | 理由 |
|---|---|---|
| "地面铺瓷砖，另做木地板铺装" | 双标 tiling+flooring | 两工种独立、工作量近 50%、各有判据 |
| "全屋铺地毯" | **单标 flooring** | 地毯属 flooring，tiling 不成立（修正 2.4 的映射伪重叠） |
| "卫生间贴砖并做防水" | 单标 tiling | 防水无独立 canonical 工种 |
| "吊顶石膏板安装，含保温棉填充" | 双标 drywall+insulation | 与现有 7 行共现一致 |
| "辅助工配合焊工" | 单标 laborer | 条件 4 |

### 4.4 白名单治理

- 准入：共现支撑 ≥5 行 **且** 通过语义审核（无工序包含关系）。现有 `MULTI_PAIR_SUPPORT = 5`（`build_trade_matcher.py:221`）。
- 现状：真实共现仅 `drywall+insulation` 7 行达标；`tiling+flooring` 18 行经 2.4 节判定为映射伪重叠，修正后预计不再达标。B3 完成后目标 3–5 对。
- 变更流程：`data/allowed_pairs.json` diff → 语义审核 → 全量回归 → 合并；**禁止与阈值改动同 commit**。

### 4.5 判不准的三级处置

| 级别 | 情形 | 处置 | 进训练 |
|---|---|---|---|
| L1 类内歧义 | 能定族但同级难分 | `primary` + `uncertain=true` + `secondary` 候选 | 复标后进 |
| L2 信息不足 | 无 4.2 优先级 1–3 判据 | `(skip)` + `skip_reason`（`too_short`/`no_trade_word`/`need_site_info`） | 不进，计入拒答率 |
| L3 体系缺失 | 工种不在 16 类内 | `(skip)` + `new_trade_candidate`，写 `reports/trade_taxonomy_gaps.md` | 不进 |

`(skip)` 是可观测信号：必须区分"数据不足的正确拒答"与"阈值过严的误拒答"——后者直接用于回归 `threshold/margin`。

### 4.6 质检与仲裁

B0 全量双标，B1–B3 按 30% 抽样双标；Cohen's κ 按类计算，任一类 <0.6 则该类重标；整体 κ≥0.75 才放量；双标签另算 `trades` 集合 Jaccard ≥0.8；三级仲裁（标注员→组长→业务专家），结论写入 `reports/annotation_decisions.md`；每批 15% 复核，错误率 >5% 整批返工。

### 4.7 易混边界（标注员必读，按实测错误重写）

| 易混对 | 口径 | 反例 |
|---|---|---|
| tiling vs flooring | tiling = 瓷砖/石材铺贴（含墙地面）；flooring = 木地板、地毯、地面找平打磨 | "铺地毯/木地板"只标 flooring |
| drywall vs masonry | drywall = 石膏板/轻钢龙骨；masonry = 砌砖砌块、抹灰 | test 实测 drywall→masonry 3 例，重点盯 |
| welding vs equipment | welding = 焊接作业本身；equipment = 吊装就位调试 | "焊设备支架"看工作量计 |
| insulation vs hvac / glazing | insulation = 保温材料铺设；hvac = 风管机组；glazing = 玻璃门窗 | "保温棉填风管"按主体判 |
| laborer vs 其他 | laborer 仅用于文本主体为辅助/搬运/清理 | "小工配合瓦工"单标 laborer |

---

## 5. 样本量与成本

### 5.1 Wilson 区间换算（脚本实算）

以 p=0.9 为参照：

| n | 95% CI | 半宽 | 含义 |
|---|---|---|---|
| 1 | 16.8–99.8% | ±41.5pp | test 中 glazing/hvac/roofing 现状 |
| 5 | 46.3–98.9% | ±26.3pp | test 中 drywall 现状 |
| 12 | 62.6–98.0% | ±17.7pp | glazing 总量 |
| 35 | 75.8–96.3% | **±10.2pp** | **每类评测下限** |
| 83 | 81.7–94.8% | ±6.6pp | 现有单集规模 |
| 248 | 85.6–93.1% | ±3.8pp | 现有训练留存 |
| 620 | 87.4–92.1% | **±2.4pp**（p=0.8 时 ±3.1pp） | 本方案冻结集 |

结论：整体要 ±3pp（p≈0.8）需约 683 行，本方案 620 行实测 ±3.1pp；逐类 ±10pp 需 35 行/类，16 类 560 + 双标签 60 = **620**，自洽。

### 5.2 汇总

| 用途 | 每类配额 | 行数 | 与现状差额 |
|---|---|---|---|
| 训练（B0/B1/B2/B3） | ≥80 | 1,372 | 518 → 1,890 |
| 冻结评测（B4） | 35 | 560 | 0 → 560 |
| 冻结集双标签 | — | 60 | 0 → 60 |
| **合计新增** | — | **1,992** | — |

### 5.3 成本（单价为可替换假设）

标注 ¥100/工时、45 行/工时；复检仲裁 ¥150/工时、30 行/工时；工程 ¥200/工时。

| 分项 | 计算 | 工时 | 金额 | 占比 |
|---|---|---|---|---|
| 标注执行 | 1,992 ÷ 45 | 44.3 h | ¥4,430 | 21% |
| 复检与仲裁 | (299 抽检 + 250 争议) ÷ 30 | 18.3 h | ¥2,745 | 13% |
| 工程 | 采样脚本、哈希隔离、回归流水线、报告 | 70 h | ¥14,000 | 66% |
| **合计** | — | **132.6 h** | **¥21,175** | 100% |

单位成本 ¥10.6/行（全额）、¥3.6/行（工程内部消化）。

### 5.4 敏感性

| 情形 | 总额 |
|---|---|
| 基准 | ¥21,175 |
| 熟练度降至 30 行/h | ¥23,385 |
| 单价降至 ¥60/h | ¥19,403 |
| 工程内部消化（0 现金） | ¥7,175 |
| 最小方案（B0 152 + B4 620 = 772 行） | ¥8,800 |

### 5.5 收益换算（只做有数据支撑的部分）

- 以 test 80.7% 为现状：每 1,000 单约 193 单需人工纠正；目标 90% 时降至 100 单，减少 **93 单/千单**。
- 冻结集把整体误差从 ±8.4pp 收窄到 ±3.1pp，McNemar 效力 0.33 → 1.00。
- 单条错派返工成本：**仓库无工时定额与返工单价，故不给 ROI**。补数据后可用 `93 × 单条返工成本 × 月单量` 计算。

### 5.6 成本结构判断

工程占 66%、标注仅 21%：瓶颈不是"多标几千行"，而是"评测与回归流水线是否一次建好"。只采购标注（¥7,175）而跳过哈希隔离与白名单回归，得到的是 1,992 行无法验证的数据。

---

## 6. 验收指标与回归流程

### 6.1 指标集（6 项）

| 指标 | 定义 | 为什么需要 |
|---|---|---|
| top-1 | 主标签命中率 | 与 80.7% / 96.4% 可比 |
| 集合严格匹配 | `trades` 集合完全一致 | 多标签唯一可验口径 |
| 宏召回 | 16 类算术平均 | 防头部类掩盖长尾 |
| 最短类召回 | glazing/roofing/hvac 均值 | 现状 test 各 1 行，等于未测 |
| 拒答率 | `(skip)` 占比，按 `skip_reason` 分解 | 现状 test 3/83=3.6%，是最大单错误源之一 |
| 次标签落地率 | 双标签样本输出 2 个工种的占比 | 现状 12 行双标签样本仅 1 行输出双标签 |

### 6.2 发布门槛（冻结集 620 行首开）

| 指标 | 现状 | 门槛 | 不达标处置 |
|---|---|---|---|
| top-1 | 80.7%（test） | ≥90%，CI 下限 ≥87% | 不发布，复查标签映射与拒答 |
| 集合严格匹配 | 未测 | ≥93% | 不发布 |
| 宏召回 | 未测 | ≥85% | 单项复议 + 长尾说明 |
| 最短类召回 | 未测 | ≥75% | 不发布 |
| 拒答率 | 3.6%（test） | 3%–8% | >8% 松 threshold；<3% 查过度自信 |
| 次标签落地率 | 1/12（8.3%） | ≥60% | 回退白名单至 1 对 |

### 6.3 评测纪律

1. 冻结集哈希写入 `reports/frozen_eval_manifest.json`，每版本只评估一次；二次开封须在 commit message 记录次数与理由；
2. 训练脚本加载前校验哈希，命中冻结集即抛错退出；
3. 新旧对比只用同一批样本做 McNemar 配对，禁止跨集比较百分比；
4. 禁止同轮"调参 + 验收"：调参只在 dev 或新增开发侧样本上做；
5. **评测产物与 artifact 绑定**：报告与 CSV 必须记录 artifact 的 SHA256 与 `built_at`，杜绝 1.3 节的版本脱钩。

### 6.4 显著性判定

方法：McNemar 精确检验 + Holm 校正（已有实现）。报告必须同时给 **Δpp、95% CI、p（校正后）、不一致样本数** 四项，缺一视为未验证。示例口径：

`"top-1 从 80.7% 提升至 91.0%（+10.3pp，95% CI +3.1～+17.5pp，McNemar p=0.004，不一致 21 修 19）"`

### 6.5 回归命令链

```text
① 数据校验  python scripts/validate_annotations.py --batch data/annotations/batch_*.jsonl
② 训练      python scripts/build_trade_matcher.py --seed 31337 --label-mode single
③ 评测      python scripts/eval_frozen.py --model data/trade_classifier.joblib \
              --manifest reports/frozen_eval_manifest.json --report reports/frozen_eval_<ver>.md
④ 核验      python scripts/verify_production_artifact.py --model data/trade_classifier.joblib
⑤ 门禁      对照 6.2 六项，全通过才允许合并 main
```

artifact 单独一个 commit，便于 revert。

### 6.6 里程碑

| 里程碑 | 时间 | 交付物 | 验收 |
|---|---|---|---|
| M1 规范可用 | 11-07 | 规范 v1.0 + B0 152 行 | 双人 κ≥0.75 |
| M1.5 映射修正 | 11-07 | `CATEGORY_MAP` 修正 + dev/test 无回归 | 双标签 25→7 |
| M2 语料到位 | 11-28 | B1/B2/B3 共 1,220 行 + QA | 重复率 ≤5%，最短类 ≥80 |
| M3 冻结集可用 | 11-28 | 620 行 + manifest | 互斥校验通过 |
| M4 首轮验收 | 12-11 | 重训 artifact + 报告 | 6.2 六项达标 |

---

## 7. 风险与回退

### 7.1 风险清单

| 类别 | 风险 | 触发 | 预防 | 应急 | 止损 |
|---|---|---|---|---|---|
| 数据 | 标注噪声抬高上限 | 某类 κ<0.6 或抽检错误 >5% | B0 全量双标、边界表、三级仲裁 | 该类重标，不进训练 | 单类错误 >8% 整批作废 |
| 数据 | 冻结集泄漏 | 训练侧哈希命中 | 互斥脚本 + 只读 manifest | 受影响结论重算，补 100 行 | 命中 1 条即判泄漏 |
| 数据 | 线上文本拿不到 | Supabase 回流为 0 | 访谈转写 + 邻域类目兜底 | 标注 `source` 区分 | 现场文本 <20% 须声明分布风险 |
| 执行 | 批次延期 | 任一延误 >3 工作日 | 并行 + 日产量看板 | 保 B1，B2 降为 30 行/类 | >5 日启动降级（7.3） |
| 效果 | 扩充后倒退 | 冻结集 top-1 < 基线 −2pp | 配对检验、逐类回归 | 回滚 artifact | −2pp 即回滚 |
| 效果 | 次标签过度触发 | 双标签输出 >25% 或 Jaccard<0.8 | 白名单 ≤5 对 + 五条件 | 收回至 1 对重训 | Jaccard<0.8 立即收回 |
| 效果 | 拒答率失控 | >8% 或 <3% | 用冻结集回归 threshold/margin | 重置 0.35/0.25 | 单次调整 >0.1 重走门禁 |
| 外部 | 合成依赖 | Gemini 配额/政策变化 | 合成 ≤40% 且只扩措辞 | 关闭合成，纯人工重训 | 占比 >40% 不发布 |

### 7.2 三级回退

| 级别 | 触发 | 动作 | 耗时 |
|---|---|---|---|
| L1 配置回退 | 拒答率异常 / 次标签过度触发 | 回退 `label_mode`、`threshold/margin` 至 single/0.35/0.25，不动 artifact | <10 分钟 |
| L2 产物回退 | 冻结集 top-1 倒退 ≥2pp | `git revert <artifact commit>`，恢复 v0 artifact，保留数据与报告 | <1 小时 |
| L3 方案回退 | 仍不达 6.2 门槛 | 回到 80.7% test 口径，结论降级为"仅单标签可用"，双标签移出本季度 | <1 天 |

前置：artifact 归档并记 SHA256；训练脚本 `--label-mode single|multi` 双向可用；白名单与阈值分 commit。

### 7.3 灰度与降级

- Shadow 2 周：新模型只记预测不派工，与线上对比人工抽检 100 单/周，连续 2 周低 5pp 即终止；
- 小流量 10%：仅头部 5 类（equipment/electrical/laborer/welding/masonry，占 55%）放量，观察 1 周；
- 砍任务顺序：B2 → B1 → B3，**B4 冻结集不得砍**（砍掉则所有结论重失验证能力）；
- 已开封冻结集不可"重开当没看过"——用于调参即降级为开发集，须另建新集。

---

## 附录 A 数字来源对照（答辩可复现）

| 数字 | 值 | 来源 |
|---|---|---|
| 原始行 / 类目数 / 标注行 | 6,539 / 864 / 518 | `eval_holdout.load_labelled_frame()` stats |
| 映射类目 / 未映射行 | 67 / 6,021 | 同上 |
| 去重标题 / 双标签行 | 517 / 25 | 同上（+`expected` 长度分布） |
| 双标签构成 | flooring+tiling 18、drywall+insulation 7 | 同上 |
| 各类全量计数 | equipment 86 … glazing 12 | 同上 |
| test top-1 | 80.7%（67/83），Wilson 71.0–87.8 | `trade_matcher_test_predictions.csv` 实算 |
| test 调参前 | 74.7%（62/83） | 同文件 `before_correct_top1` 列 |
| McNemar | 修 6 破 1，p=0.125 | 同文件配对实算 |
| valid / V0 | 96.4% / 92.8% | `reports/trade_synthetic_multilabel.md` 登记口径 |
| valid CSV 快照 | 89.2%（74/83） | `trade_matcher_valid_predictions.csv`（旧 artifact） |
| 混淆对 | 见 2.3 表 | 三份 predictions CSV 实算 |
| 多标签输出次数 | 1/270 | 同上（`predicted` 含 `;` 或 `|`） |
| 双标签样本数 | dev 6 / test 4 / valid 2 | 同上（`expected` 含 `;`） |
| 模型 meta | samples=4591、C=4.0、single、0.35/0.25、sklearn 1.5.2 | `joblib.load("data/trade_classifier.joblib")` |
| 合成语料 | 训练侧 3,074（raw 4,440，kept 3,619） | `reports/synthetic_trade_stats.json` |
| 合成类分布 | equipment 512 / glazing 92 | 同上 `per_trade_kept` |
| Wilson 表 / 效力曲线 | 见 5.1 / 2.2 | 本文件当次计算（p=0.9、4,000 次模拟） |
| 本地 DB 计数 | tasks/workers/prediction_history = 0；无 ai_decision_log 表 | `sqlite3 construction_management.db` 实查 |
*（内容由AI生成，仅供参考）*
