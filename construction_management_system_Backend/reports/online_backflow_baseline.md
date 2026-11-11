---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f3d7249bacac4923999ceda47b8083c_e1f1c903d38a11f18d9e525400393706
    ReservedCode1: CNRQeS5lyLeWCR90Bc15scKO/xSITY6zSn+Bt7JMi+CsBPYK+7uzxns+MLeEcGix/m8drjhF6o87xPGcgSL3M765M3uJrzXZO2kUZ8bnKS1DnOwr59GHgHe5PtiLU/XHqOpX/wSnmC5m6onOBbCs4nDbKnkx265hed6fEVtBmqYRGGBwuyElfewh7pI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f3d7249bacac4923999ceda47b8083c_e1f1c903d38a11f18d9e525400393706
    ReservedCode2: CNRQeS5lyLeWCR90Bc15scKO/xSITY6zSn+Bt7JMi+CsBPYK+7uzxns+MLeEcGix/m8drjhF6o87xPGcgSL3M765M3uJrzXZO2kUZ8bnKS1DnOwr59GHgHe5PtiLU/XHqOpX/wSnmC5m6onOBbCs4nDbKnkx265hed6fEVtBmqYRGGBwuyElfewh7pI=
---

# 线上回流基线（2026-10-29 实测）

> 目的：把 `reports/trade_label_expansion_plan.md` §3.4 第 1 项"线上回流核验"从假设变成数字。
> 采集方式：`psycopg2` 直连 `.env` 中的 `DATABASE_URL`（Supabase 连接池 `aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres`），只执行 `select`，未做任何写入。
> 采集时间：2026-10-29 18:5x（UTC+8）。

## 1. 表存在性与行数

| 表 | 是否存在 | 行数 | 说明 |
|---|---|---:|---|
| `tasks` | 是 | 4 | 其中仅 2 行有 `trade` 值 |
| `workers` | 是 | 6 | |
| `ai_decision_log` | **是** | **0** | 表与索引都已存在（此前"只在 Postgres 迁移路径创建、线上可能没有"的判断不成立） |
| `prediction_history` | 是 | 2 | 进度预测流水，非工种标签 |
| `task_progress_logs` | 是 | 4 | |

`users` 表不存在（该库走 `supervisors` / `workers` 双表建模）。

## 2. `ai_decision_log` 线上结构（已就绪）

列：`log_id, stage, task_id, project_id, task_text, rule_trades, semantic_scores, final_trade, source, confidence, elapsed_ms, llm_used, llm_reason, skip_reason, was_overridden, override_trade, created_at`

索引：`ai_decision_log_pkey(log_id)`、`ix_ai_decision_log_log_id`、`ix_ai_decision_log_task_id`、`ix_ai_decision_log_was_overridden`、`ix_ai_decision_log_project_created_stage(project_id, created_at, stage)`

结论：**§3.4 第 6 项"线上建 ai_decision_log 表及索引"不需要再做**，线上早已具备，且索引覆盖了按项目 + 时间 + 阶段分页的查询形态（`ai_stats.py` 的读取路径）。

## 3. 真实回流规模（关键结论）

| 观测量 | 值 |
|---|---:|
| 线上 `tasks` 总数 | 4 |
| 有 `trade` 标签的 `tasks` | 2（`plumbing` 1、`electrical` 1） |
| 可用于训练/评测的文本 | 2 条（`fixing plumbing`、`electric`），均为冒烟测试文本 |
| `ai_decision_log` 已落盘决策 | 0 |
| `prediction_history` | 2 |

**判断：线上回流目前提供 0 条可用训练数据，`prediction_history` 缓存命中 2 条（`bcs2402048@student` 项目），与 518 行标注集相比可忽略。**

因此：

1. §3.2 的 B1–B3 分批采样**必须**走人工标注 + 受控合成，不能假设"线上会自然积累"再等数据。
2. §3.1 里"真实文本优先"的口径不变，但现阶段真实文本来源只能是 backfill 已有的 518 行 + 手工新标，而不是线上库导出。
3. `ai_decision_log` 表在却 0 行，说明**写入路径尚未在真实业务流中被触发或被跳过**：创建任务时若走的是 `tasks.trade` 直接赋值（如 `ai.py` 的人工指定分支），不会产生决策日志。这点需要在下一轮确认为产品预期还是缺口——它决定未来"线上回流"是否真的会自己长数据。

## 4. 对扩充方案的影响

- §3.4 前置项 1（线上核验）**已完成**，数字即本文。
- §3.4 前置项 6（建表）**无需执行**，线上已就绪，改为"确认写入路径是否会产出日志"。
- `prediction_history` 2 行、`tasks` 4 行意味着当前没有任何可用于"冻结集首开 620 行"的存量，§5 的样本量结论继续成立：需要新标 620 行才能拿到 ±6pp 级别的区间。
*（内容由AI生成，仅供参考）*
