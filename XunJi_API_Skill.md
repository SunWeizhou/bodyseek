> 这是训记 Open API 的集成说明，不是 BodySeek 产品规格。产品以 `docs/PRD.md` 为准。现行 App 仍会读取训记训练数据。

“请启用下面这份训记训练数据 Open API skill。需要导入、导出、整理或写回训练时，严格遵守鉴权、限频、缓存和写回确认规则；动作只使用中文名，不要使用或暴露内部 key。

# 训记训练数据 Open API Skill

## 原则
- 只在用户明确要求读取、整理或写回训练数据时调用接口。
- 写回前必须先展示变更摘要，并等待用户确认。
- 按 `datestr` 缓存读取结果；同一天不要重复请求。

## 鉴权
- 请求头: `Authorization: Bearer <在 App 里申请并获取 Key 后替换这里>`
- 也兼容请求头 `x-api-key`。
- 不支持把 Key 放在 body 或 query 里。
- 不要把 Key 写入日志或展示给第三方。

## 接口
- Base URL: `https://trains.xunjiapp.cn`
- 读取训练: `POST /api_trains_for_llm_v2`
- 写回训练: `POST /api_upsert_trains_for_llm_v2`
- 成功时 `success === true`，核心数据在 `res`。
- 标准动作中文名: `https://github.com/Foveluy/Xunji-movements`

## 读取
```http
POST https://trains.xunjiapp.cn/api_trains_for_llm_v2
Authorization: Bearer <在 App 里申请并获取 Key 后替换这里>
Content-Type: application/json

{
  "schema_version": "train_open_api_v2",
  "datestr": "2026-04-02",
  "include_full_data": false
}
```

- 默认 `include_full_data: false`，只返回轻量数据，接近 v1。
- 需要未打勾组、RPE、备注、完成感受、左右侧重量或实练秒数时，传 `include_full_data: true`。
- 有氧、计时、Tabata、苹果健康等记录型动作会在 `sets[].metrics` 返回 distance/kcal/calories/workoutTime/avgHeartRate/maxHeartRate 等摘要指标。
- 苹果健康训练的 `name` 返回运动类型，例如 `Running`；老数据会尽量从训练标题推断。
- 超级组/递减组会在 `sets[].items[]` 返回子动作；每个子项的 `set` 里有 weight/unit/reps/time/metrics。
- 返回里的训练在 `res.trains`；写回旧训练时保留 `localid`、`start`、`end`。
- 动作不会暴露内部 key；需要标准动作名时读取 GitHub 动作名表。

## 写回
```http
POST https://trains.xunjiapp.cn/api_upsert_trains_for_llm_v2
Authorization: Bearer <在 App 里申请并获取 Key 后替换这里>
Content-Type: application/json

{
  "schema_version": "train_open_api_v2",
  "client_request_id": "unique-id-from-agent",
  "dry_run": false,
  "include_full_data": false,
  "res": [
    {
      "datestr": "2026-04-02",
      "localid": 123456,
      "title": "胸部训练",
      "start": 1744010000000,
      "end": 1744013600000,
      "movements": [
        { "name": "杠铃卧推", "sets": [
          { "done": true, "weight": "60", "unit": "kg", "reps": "10" }
        ] }
      ]
    }
  ]
}
```

## 写回规则
- 写回动作只传中文 `name`，不要传 `key`；服务端会按中文名查找并回填内部 key。
- 不确定中文名时，先读取 `https://github.com/Foveluy/Xunji-movements`，只从表里的中文名里选择。
- `res` 可以是训练数组，也可以是 `{ "trains": [...] }`；单次最多 4 条训练，且必须属于同一天。
- 每条训练最多 15 个动作；每个动作最多 20 组，超过会被服务端拒绝。
- 有 `localid` 时更新原训练；没有 `localid` 时新建训练；不要因为列表里缺少旧训练就删除旧训练。
- 更新旧训练时保留 `localid`、`start`、`end`，除非用户明确要改时间。
- 组至少包含 `weight`/`weight_kg`、`reps`、`time`/`duration_s`、`selfWeight` 之一。
- 未完成组用 `done: false`；不要把完整模式读到的未完成组擅自删掉。
- 写回成功后，用服务端返回的标准化 `res` 覆盖缓存。

## 限频与错误
- 同一个训练日 90 秒内最多读取一次；`too frequent` 时等待提示的 retry 时间。
- 不确定动作名时不要编造；让用户确认中文动作名后再写回。
- `apikey missing` / `apikey invalid`: 让用户回 App 复制或重新申请 Key。
- `仅VIP可用`: 当前账号需要会员权限。
”
我训记账号的API key是：xjllm_c71d875917317b6f82d06d61a0b29d25fc218c8c804d6e16