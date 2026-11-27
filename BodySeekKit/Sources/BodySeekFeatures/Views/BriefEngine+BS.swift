import BodySeekAgent
import BodySeekDesign

extension BSBriefEngine {
    /// 把简报引擎映射到 `BSCoachNote` 用的来源标注；没有简报时按本地模板处理。
    init(_ engine: BriefEngine?) {
        switch engine {
        case .some(.cloud): self = .cloud
        case .some(.onDevice): self = .onDevice
        case .some(.localTemplate), .none: self = .localTemplate
        }
    }
}
