# BuildSmart 测试报告

**日期：** 2026-11-14（Asia/Singapore）
**测试版本：** GitHub commit `f2879aa`
**线上网站：** https://xkin248.github.io/Construction-management-system-empowered-by-AI/
**部署状态：** GitHub Pages 部署成功

## 1. 测试结论

本轮已完成后端自动回归测试、Flutter 静态分析和 GitHub Pages release build。已确认的权限、审核状态与同步问题已修复。

**目前状态：可进入人工验收测试，但尚未等同于真实现场正式验收通过。**

相机、GPS 围栏、Firebase、Supabase 文件预览下载及 Android 强杀恢复，仍必须由人工在真实浏览器/Android 模拟器或真机完成验证。

## 2. 自动测试结果

| 范围 | 命令/方式 | 结果 |
|---|---|---|
| 后端完整测试 | `python -m pytest -q -rA` | PASS — 无失败案例 |
| 新增考勤权限回归 | 未登入、工人、主管访问 attendance summary / weekly stats | PASS |
| 文件跨主管隔离 | 第二名主管列出、下载、编辑、删除他人项目文件 | PASS — 已拒绝 |
| Approved 任务状态 | Worker task board、完成统计、同步更新时间 | PASS |
| Python 编译检查 | `python -m compileall app` | PASS |
| Flutter 静态分析 | `flutter analyze` | PASS |
| Web release build | GitHub Actions Build Flutter Web | PASS |
| GitHub Pages 部署 | GitHub Actions Deploy to GitHub Pages | PASS |

## 3. 已修复项目

| ID | 修复内容 | 验证方式 |
|---|---|---|
| FIX-01 | 考勤 Today、指定工人 Today、Weekly Stats 需要登入，并限制到主管自己的项目 | 自动权限回归测试 |
| FIX-02 | 文件 upload/list/download/update/delete 按当前主管所属项目限制 | 自动跨主管文件测试 |
| FIX-03 | `approved` 与旧 `completed` 一律视为任务完成 | 自动 worker task board 测试 + 后端回归 |
| FIX-04 | Approved 任务不会进入 AI Auto-Assign 的可重新派工清单 | 后端状态逻辑测试 |
| FIX-05 | 工人完成照片使用认证请求读取 | Flutter 静态检查；需人工打开图片确认 |
| FIX-06 | Worker task sync 使用稳定更新时间，避免每次轮询都回传完整资料 | 自动 sync 回归测试 |
| FIX-07 | Attendance 页面显示实际选中的项目名称 | Flutter 静态检查；需人工切换项目确认 |
| FIX-08 | Worker task board 明确标示为规则式工作指引，不再宣称实时 AI confidence | 代码审查 + Flutter 静态检查 |

## 4. 必须人工测试（未可由自动测试替代）

请使用 [MANUAL_UAT_CHECKLIST_ZH.md](MANUAL_UAT_CHECKLIST_ZH.md) 逐项勾选。以下为上线前优先项：

- [ ] **R01** 工人提交照片 → 主管 Approve → 工人任务进入 Completed。
- [ ] **R02** Approved 任务在 Dashboard、项目详情、AI prediction 显示正确。
- [ ] **R03** 主管与工人都能打开完成照片。
- [ ] **R04** Reject 不填写理由时被阻止。
- [ ] **R05** 无痕/登出后不能查看考勤资料。
- [ ] **R06** 切换 Project A/B 时 Tasks、Workers、Attendance、Files 同步。
- [ ] **R07** 错误密码保留表单内容并显示错误。
- [ ] **R08** Android 强杀重开保持登入；Logout 后必须回 Login。
- [ ] **G01–G08** GPS 围栏、相机自拍、拒绝权限、围栏外打卡。
- [ ] **F01–F08** 图片/PDF 上传、预览、下载、删除、跨项目隔离、断网重试。

## 5. AI 功能说明

当前 AI Auto-Assign 以可解释规则为主：项目范围、required skill level、trade/specialty 和候选条件。它会在资料不完整时拒绝/提示，而不是随机派工。

目前**不承诺**按距离、未来排程、实际工作量、工人偏好或生产效率进行智能预测。这些属于下一阶段的 AI 能力，不应被写成已完成测试项。

## 6. 上线建议

自动测试已通过，但在以下项目全部通过前，建议不要把版本交给真实工地使用：

1. R01–R08 全部通过；
2. GPS 围栏内/外与相机自拍通过；
3. 文件上传、预览、下载、跨项目权限通过；
4. 至少以两名主管、两名工人完成一次权限隔离测试。

## 7. 问题回报格式

```text
案例编号：例如 R03
严重性：P0 / P1 / P2
环境：网页 / Android；本地 / 线上；设备与浏览器版本
帐号角色：主管 / 工人（不要写密码）
项目、任务或文件 ID：
操作步骤：
预期结果：
实际结果：
发生时间与网络状态：
截图或录屏：
是否可重复：每次 / 偶尔 / 一次
```
