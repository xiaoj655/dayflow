---
name: dayflow
description: 管理用户 Dayflow 手表和手机共享的每日任务、固定习惯、任务教程及专注记录；直接操作其 MySQL 数据库。
---

# Dayflow

使用本技能安排每日事项、创建或调整重复习惯、补充执行方法或技巧教程、查询完成情况和专注记录。手表与手机直连同一数据库，不经过后端 API。

## 连接与运行

连接信息以明文保存在技能目录的 `connection.json`；公开源码只提供 `connection.example.json`，使用者复制后填写自己的配置。`mysql-server.pem` 由使用者通过可信渠道提供，是其服务器的固定 TLS 叶证书；不包含服务器私钥。不要把密码拼进命令行或打印给用户，不提交真实配置或证书。证书验证失败时说明连接失败，不自动信任新证书。

需要 Python 3.10+ 和 PyMySQL。环境缺少依赖时，在技能目录创建 `.venv` 并执行 `.venv/bin/pip install -r requirements.txt`。使用 `${HERMES_SKILL_DIR}/scripts/tasks.py`，命令示例中的 `python` 替换为可用的 Python 或该虚拟环境解释器。

```bash
python "${HERMES_SKILL_DIR}/scripts/tasks.py" list --date 2026-10-24
python "${HERMES_SKILL_DIR}/scripts/tasks.py" put --input /path/to/task.json
python "${HERMES_SKILL_DIR}/scripts/tasks.py" put --id TEMPLATE_UUID --input /path/to/changes.json
python "${HERMES_SKILL_DIR}/scripts/tasks.py" complete --id 'TEMPLATE_UUID:2026-10-24'
python "${HERMES_SKILL_DIR}/scripts/tasks.py" complete --id 'TEMPLATE_UUID:2026-10-24' --undo
python "${HERMES_SKILL_DIR}/scripts/tasks.py" carry --id 'TEMPLATE_UUID:2026-10-24'
python "${HERMES_SKILL_DIR}/scripts/tasks.py" archive --id TEMPLATE_UUID
python "${HERMES_SKILL_DIR}/scripts/tasks.py" history --limit 30
```

`init` 用于准备或升级数据库；创建缺失的表，并幂等补充 v2 的五个任务详情字段与 v3 的跨日来源字段，不清空数据、不改写历史快照。现有表结构见 [references/schema.sql](references/schema.sql)。

## 任务格式

通过 JSON 文件传递文本，保留中文和换行，不将用户内容插进 SQL 或 shell 命令。

```json
{
  "title": "街头观察",
  "content": "散步时观察步速和姿态，用三条简短描述记录发现。",
  "tutorial": "每次只观察一个维度。先描述细节，再区分自己的猜测。",
  "task_value": "提升观察与表达能力",
  "minimum_goal": "记录一个具体细节",
  "completion_standard": "留下一条能区分事实与猜测的观察笔记",
  "start_action": "先观察一个路口",
  "estimated_minutes": 15,
  "date": "2026-10-24",
  "recurrence": "once",
  "weekdays": [],
  "sort_order": 0
}
```

- `title` 与 `content` 必填；`tutorial` 可省略或设为 null。教程写用户能执行的方法、步骤和要点；需要外部知识时先核实，不把猜测写成事实。
- `task_value` 解释为什么做；`minimum_goal` 是最低要做到什么；`completion_standard` 是可检验的达成标准；`start_action` 是能立刻执行的第一步。四个字段均为可选文本，可设 null 清空；补充这些内容时保留用户意图，不擅自提高目标。
- `estimated_minutes` 是整项任务预估分钟数，可省略或设 null，填写时为 1–1440 的整数。它独立于番茄钟时长，不必是 5 的倍数，也不覆盖手表记住的专注时长。
- `date` 是亚洲/上海时区的安排日期，重复任务则是开始日期。省略时使用该时区的今天。
- `recurrence` 为 `once`、`daily` 或 `weekly`；每周任务用 `weekdays` 指定周一=1 至周日=7。
- `sort_order` 越小越靠前。同一份安排内保持顺序稳定；完成任务自动显示在未完成任务下方。
- 修改时先查询定位 ID；标题相同可能属于不同日期，不凭标题批量更新。`put --id` 保留没有传入的字段，适合单独补教程。

## 工作方式

用户要求安排或修改任务即授权执行对应修改，不重复索要常规确认。先明确日期、标题和实际要做的内容；无法从上下文推断时，只问影响安排的缺失信息。一次性安排不要擅自变成每日习惯。

生活任务可按日期查看。要将其他日期未完成的任务加入今天，先 `list --date` 定位每日任务 ID，再执行 `carry --id`；昨天或明天的任务都可选，已完成或本来就在今天的任务不可转入。此操作保留原日期快照，不修改模板或重复规则；今天同一模板已有任务时去重，并保留它已有的完成状态。`carried_from_date` 记录来源日期，仅供识别，不作为用户输入修改。

固定习惯是模板，每天的完成状态是独立记录。`list` 会幂等生成指定日期的记录；更新生活模板不会改写过去日期或已完成任务的内容；工作任务未完成时持续更新原记录。停用任务用 `archive`，保留历史，不删除记录。

专注时长以五分钟递增，记忆上次实际开始的专注时长。计时、专注勿扰和震动由手表本地负责。Hermes 可查询专注记录，不能代替手表启动计时，不能将完成一轮专注当成任务完成，也不伪造专注记录。

写入超时或连接中断后，先查询对应日期核实是否已提交，再决定是否重试；不要盲目重复创建。

修改后再次 `list` 对应日期确认结果，再用简短中文说明完成的安排；不回显连接密码。

当前不支持定时提醒、稍后提醒或今天跳过，用户已将此功能延期。不要声称仅通过数据库写入就能主动推送到手表。

## 工作与生活空间

任务 payload 的 `space` 为 `life`（默认）或 `work`；`list --space work` / `list --space life` 可筛选。编辑已有模板时省略该字段会保留原值。每日快照及专注记录保留各自空间，修改模板不改写过去或已完成记录；不得伪造专注记录。升级已有数据库使用增量迁移，旧数据默认归入生活空间。


工作空间是本周任务池，不按天重复生成。`list --space work` 显示持续保留的未完成任务和本周完成任务，忽略历史日期切换。新建工作任务使用 `once`，默认今天进入任务池；不安排未来周。待推进与等待中跨周保留同一个 ID，不执行 `carry`。旧模板存在多个工作快照时，未完成任务只展示截至今天最新的一条，旧记录和专注关联不删除。

- `waiting --id TASK_ID`：设为等待中；加 `--undo` 恢复待推进。完成后撤销保留原等待状态。
- `work-history`：查询工作完成记录，包括之前周的记录。
- `init` 和项目迁移脚本幂等补充 `waiting` 字段。发布新客户端前先迁移。
