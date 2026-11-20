# 记餐与证据链的复用依据

核对日期：2026-11-20。这里记录上游接口、现有实现和接入取舍，模型与第三方接口兼容性需用实际配置验证。

## 输入与能力

- 相册沿用系统 PhotosPicker，只处理用户选中的图片。直接拍照沿用系统相机入口，在设备有相机时开启。Vision 原生文本识别适合从包装、菜单和营养标签提取字符；它只是 OCR，不能识别无文字餐盘里有什么，也不能估出重量、调味油或可食部。 [Apple PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker) · [Apple 相机入口](https://developer.apple.com/documentation/uikit/uiimagepickercontroller/sourcetype-swift.enum/camera) · [Apple Vision OCR 示例](https://developer.apple.com/documentation/vision/locating-and-displaying-recognized-text)
- 可复用现有 OpenAI 兼容供应商配置。Chat Completions 的多模态用户消息用 `content` 数组，包含文本块和 `image_url` 块。官方文档允许图片 URL 或 Base64 data URL；发送本地图片无需另建图床。模型、供应商和网关分别决定图片能力，文字接口通过不能当作图片能力通过。目前 DeepSeek 文档明确列出的视觉模型是 `deepseek-flash`，不能据此假定任何已配置的自定义模型支持图片。图片发出前显示接收端，先缩图并去除原始元数据；兼容失败仍可退到文字或手动录入。 [OpenAI 图像输入](https://developers.openai.com/api/docs/guides/images-vision?api-mode=chat) · [DeepSeek 视觉](https://api-docs.deepseek.com/guides/vision/)
- 模型只输出待核对的食物、烹饪状态、份量线索和单位。支持 JSON Schema 的端点可用 Structured Outputs，其余接口沿用现有 JSON 工具调用或经过结构校验的 JSON 回复。无论供应商是否支持严格模式，客户端都要拒绝无效单位、非正数份量和不可解释的数据，把「一碗」「两块」保留为待补的份量线索。 [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) · [现有消息结构](../../BodySeekKit/Sources/BodySeekAgent/OpenAICompatibleClient.swift#L307)

## 本地匹配、换算和保存

- 复用现有 GRDB 食物库检索、别名和来源字段。优先匹配明确的生熟状态和食物条目，由 `FoodLibraryItem.makeMealEntry` 按库中基准份量换算本次摄入；不要求模型编写营养成分。MEXT 标准表本身按可食部每 100 g 给标准值，并不表示用户实际餐盘份量。找不到可靠匹配、g/mL 不一致、复合菜成分不明时留下待确认项，不用相似条目或零补齐。 [MEXT 食品成分表及说明](https://www.mext.go.jp/a_menu/syokuhinseibun/index.htm) · [食物库检索](../../BodySeekKit/Sources/BodySeekStore/BodySeekRepository.swift#L1743) · [本地换算](../../BodySeekKit/Sources/BodySeekCore/NutritionModels.swift#L938)
- 文字、照片和手动都可进入同一编辑表单。确认前保留「识别出的食物」「用户确认的份量」「食物成分来源」三层。按餐提交可复用 `ActionProposal` 和 GRDB 事务，让整餐和审计一并保存；草稿或重试使用稳定条目 ID。餐中有估算或缺项应保留标记，完成一餐不等于当天饮食记录已完成。Agent 分析继续读 `get_eating_context`，扩充估算、部分记录的区分。 [现有餐食记录](../../BodySeekKit/Sources/BodySeekCore/NutritionModels.swift#L990) · [现有事务入口](../../BodySeekKit/Sources/BodySeekStore/ActionExecutor.swift#L113) · [现有营养工具](../../BodySeekKit/Sources/BodySeekAgent/CoachToolRegistry.swift#L839)
- 可借 W3C PROV-O 的 `wasDerivedFrom` 表达血缘：营养换算结果可追到食物条目和份量，模型草稿可追到识别入口，确认者与估算者分开。BodySeek 现有类型和 GRDB 可以承载这些关系，本阶段没有增加专用存储的需要。 [W3C PROV-O](https://www.w3.org/TR/prov-o/)

## 相邻模块

- Coach 保留已有 Textual，沿用上游结构化文本的标题、段间距、列表和表格样式 API，配合简短回答契约。原生证据卡继续承担来源和确认操作。趋势继续复用既有 Swift Charts 与社区组件。 [Textual 样式](https://github.com/gonzalezreal/textual#styling) · [现有渲染](../../BodySeekKit/Sources/BodySeekFeatures/Views/CoachMarkdownReply.swift) · [项目图表复用记录](chart-reuse-evaluation-2026-11-20.md)
- HealthKit 观察查询通知有变化，锚点查询提供新增和删除及下一个游标；两者职责不同。沿用现有查询做增量导入，事务成功后再提交游标。手机本地写入通过数据库修订主动刷新，手表写入则从 HealthKit 实际到达时计量，避免承诺随时立即送达。 [Apple 观察查询](https://developer.apple.com/documentation/healthkit/executing-observer-queries) · [Apple 锚点查询](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
