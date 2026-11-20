import BodySeekCore
import XCTest

final class WorkoutReviewParserTests: XCTestCase {
    private struct LabeledCase {
        let text: String
        let expectedPrimary: Set<BodyRegionMuscle>
        let expectedSecondary: Set<BodyRegionMuscle>
        let excludedMuscles: Set<BodyRegionMuscle>
        let expectedRPE: Int?
        let expectedExercises: Set<String>
        let expectedSignalCount: Int

        init(
            text: String,
            expectedPrimary: Set<BodyRegionMuscle>,
            expectedSecondary: Set<BodyRegionMuscle> = [],
            excludedMuscles: Set<BodyRegionMuscle> = [],
            expectedRPE: Int?,
            expectedExercises: Set<String>,
            expectedSignalCount: Int
        ) {
            self.text = text
            self.expectedPrimary = expectedPrimary
            self.expectedSecondary = expectedSecondary
            self.excludedMuscles = excludedMuscles
            self.expectedRPE = expectedRPE
            self.expectedExercises = expectedExercises
            self.expectedSignalCount = expectedSignalCount
        }
    }

    func testParserAccuracyAcrossFiftyFiveRealChineseWorkoutReviews() {
        let cases: [LabeledCase] = [
            // 1-10: Chest / Push
            LabeledCase(text: "今天练胸，平板杠铃卧推 4 组加蝴蝶机夹胸，RPE 8", expectedPrimary: [.chest], expectedSecondary: [.triceps, .deltoids], expectedRPE: 8, expectedExercises: ["杠铃卧推", "夹胸/飞鸟"], expectedSignalCount: 0),
            LabeledCase(text: "上斜哑铃卧推 5 组，双杠臂屈伸 3 组，主观努力度 8，右肩前束有点紧", expectedPrimary: [.chest, .deltoids, .triceps], expectedRPE: 8, expectedExercises: ["上斜卧推", "双杠臂屈伸"], expectedSignalCount: 1),
            LabeledCase(text: "推力日，卧推、哑铃推举和绳索下压，挺累的", expectedPrimary: [.chest, .deltoids, .triceps], expectedRPE: 8, expectedExercises: ["卧推", "哑铃推举", "三头臂屈伸"], expectedSignalCount: 0),
            LabeledCase(text: "俯卧撑 5 组恢复为主，微汗", expectedPrimary: [.chest], expectedRPE: 5, expectedExercises: ["俯卧撑"], expectedSignalCount: 0),
            LabeledCase(text: "哑铃卧推 4x8 RPE 7.5，强度适中", expectedPrimary: [.chest], expectedRPE: 8, expectedExercises: ["哑铃卧推"], expectedSignalCount: 0),
            LabeledCase(text: "今天主练上胸和三头，上斜卧推拉爆，感觉力竭，手腕微痛", expectedPrimary: [.chest, .deltoids, .triceps], expectedRPE: 9, expectedExercises: ["上斜卧推"], expectedSignalCount: 1),
            LabeledCase(text: "推胸 4 组，飞鸟 3 组，今天没练腿，RPE 7", expectedPrimary: [.chest], expectedSecondary: [.triceps, .deltoids], excludedMuscles: [.quadriceps, .calves], expectedRPE: 7, expectedExercises: ["卧推", "夹胸/飞鸟"], expectedSignalCount: 0),
            LabeledCase(text: "双杠臂屈伸 4 组加卧推 4 组，右肘不适", expectedPrimary: [.chest, .triceps], expectedRPE: nil, expectedExercises: ["双杠臂屈伸", "卧推"], expectedSignalCount: 1),
            LabeledCase(text: "推日结束，平板卧推 65kgx8，侧平举 4 组，RPE 8", expectedPrimary: [.chest, .deltoids, .triceps], expectedRPE: 8, expectedExercises: ["杠铃卧推", "侧平举"], expectedSignalCount: 0),
            LabeledCase(text: "器械推胸 4 组，挺累", expectedPrimary: [.chest], expectedRPE: 8, expectedExercises: ["卧推"], expectedSignalCount: 0),

            // 11-20: Back / Pull
            LabeledCase(text: "练背，引体向上 5 组，高位下拉 4 组，RPE 8", expectedPrimary: [.upperBack], expectedSecondary: [.biceps, .forearm], expectedRPE: 8, expectedExercises: ["引体向上", "高位下拉"], expectedSignalCount: 0),
            LabeledCase(text: "拉力日，坐姿划船加面拉，RPE 7，左腰略紧", expectedPrimary: [.upperBack, .biceps, .deltoids], expectedRPE: 7, expectedExercises: ["划船", "面拉"], expectedSignalCount: 1),
            LabeledCase(text: "俯身杠铃划船 4 组和二头弯举 3 组，很累", expectedPrimary: [.upperBack, .biceps], expectedRPE: 8, expectedExercises: ["杠铃划船", "弯举"], expectedSignalCount: 0),
            LabeledCase(text: "单臂哑铃划船配直臂下压，中等强度，今天没练肩", expectedPrimary: [.upperBack], expectedSecondary: [.biceps, .triceps], excludedMuscles: [.deltoids], expectedRPE: 7, expectedExercises: ["划船", "直臂下压"], expectedSignalCount: 0),
            LabeledCase(text: "高位下拉、锤式弯举和耸肩，RPE 9，几乎力竭", expectedPrimary: [.upperBack, .biceps, .trapezius], expectedRPE: 9, expectedExercises: ["高位下拉", "弯举", "耸肩"], expectedSignalCount: 0),
            LabeledCase(text: "山羊挺身强化下背，加悬垂举腿，轻松完成", expectedPrimary: [.lowerBack, .abs], expectedRPE: 5, expectedExercises: ["山羊挺身", "悬垂举腿"], expectedSignalCount: 0),
            LabeledCase(text: "引体向上拉爆了，小臂发紧，力竭", expectedPrimary: [.upperBack], expectedSecondary: [.biceps, .forearm], expectedRPE: 9, expectedExercises: ["引体向上"], expectedSignalCount: 1),
            LabeledCase(text: "背阔肌为主，坐姿划船 4 组，农夫行走 3 组，RPE 8", expectedPrimary: [.upperBack, .forearm], expectedRPE: 8, expectedExercises: ["划船", "农夫行走/前臂"], expectedSignalCount: 0),
            LabeledCase(text: "面拉和后束飞鸟练上背和肩，RPE 6", expectedPrimary: [.deltoids, .upperBack], expectedRPE: 6, expectedExercises: ["面拉", "后束飞鸟"], expectedSignalCount: 0),
            LabeledCase(text: "哑铃划船和杠铃弯举，今天跳过腹肌，主观努力度 7", expectedPrimary: [.upperBack, .biceps], excludedMuscles: [.abs], expectedRPE: 7, expectedExercises: ["划船", "弯举"], expectedSignalCount: 0),

            // 21-32: Legs & Glutes
            LabeledCase(text: "今天腿日，杠铃深蹲 5x5 加腿举，RPE 9，右膝有点紧", expectedPrimary: [.quadriceps, .gluteal, .hamstring], expectedRPE: 9, expectedExercises: ["深蹲", "腿举"], expectedSignalCount: 1),
            LabeledCase(text: "罗马尼亚硬拉和俯卧腿弯举，主攻后链臀腿，RPE 8", expectedPrimary: [.hamstring, .gluteal], expectedRPE: 8, expectedExercises: ["罗马尼亚硬拉", "腿弯举"], expectedSignalCount: 0),
            LabeledCase(text: "保加利亚分腿蹲加臀推，很累，大腿前侧酸痛", expectedPrimary: [.quadriceps, .gluteal], expectedRPE: 8, expectedExercises: ["保加利亚分腿蹲", "臀推"], expectedSignalCount: 1),
            LabeledCase(text: "传统硬拉 4 组和提踵 4 组，下背发紧，RPE 8", expectedPrimary: [.hamstring, .lowerBack, .gluteal, .calves], expectedRPE: 8, expectedExercises: ["硬拉", "提踵"], expectedSignalCount: 1),
            LabeledCase(text: "下肢训练：前蹲和坐姿腿屈伸，正常节奏", expectedPrimary: [.quadriceps, .gluteal, .hamstring], expectedRPE: 7, expectedExercises: ["深蹲", "坐姿腿屈伸"], expectedSignalCount: 0),
            LabeledCase(text: "箭步蹲 3 组加小腿提踵，轻松恢复", expectedPrimary: [.quadriceps, .gluteal, .calves], expectedRPE: 5, expectedExercises: ["箭步蹲", "提踵"], expectedSignalCount: 0),
            LabeledCase(text: "硬拉冲大重量到力竭，左膝刺痛", expectedPrimary: [.hamstring, .lowerBack, .gluteal], expectedRPE: 9, expectedExercises: ["硬拉"], expectedSignalCount: 1),
            LabeledCase(text: "练腿和练臀，腿举配罗马尼亚硬拉，RPE 8", expectedPrimary: [.quadriceps, .gluteal, .hamstring], expectedRPE: 8, expectedExercises: ["腿举", "罗马尼亚硬拉"], expectedSignalCount: 0),
            LabeledCase(text: "哈克深蹲 4 组加腿弯举 4 组，右跟腱不适，吃力", expectedPrimary: [.quadriceps, .gluteal, .hamstring], expectedRPE: 8, expectedExercises: ["深蹲", "腿弯举"], expectedSignalCount: 1),
            LabeledCase(text: "臀推 4 组，坐姿踢腿 3 组，没有做硬拉，RPE 7", expectedPrimary: [.gluteal, .quadriceps], expectedSecondary: [.hamstring], excludedMuscles: [.lowerBack], expectedRPE: 7, expectedExercises: ["臀推", "坐姿腿屈伸"], expectedSignalCount: 0),
            LabeledCase(text: "腿日完全力竭，深蹲和箭步蹲 RPE 10，双侧膝盖疼痛", expectedPrimary: [.quadriceps, .gluteal, .hamstring], expectedRPE: 10, expectedExercises: ["深蹲", "箭步蹲"], expectedSignalCount: 1),
            LabeledCase(text: "直腿硬拉 4 组强化腘绳肌，RPE 7", expectedPrimary: [.hamstring, .gluteal], expectedRPE: 7, expectedExercises: ["罗马尼亚硬拉"], expectedSignalCount: 0),

            // 33-44: Shoulders, Arms, Core
            LabeledCase(text: "肩部专项：站姿过头推举配侧平举，RPE 8", expectedPrimary: [.deltoids], expectedRPE: 8, expectedExercises: ["过头推举", "侧平举"], expectedSignalCount: 0),
            LabeledCase(text: "杠铃推举和前平举，右肩酸痛，挺累", expectedPrimary: [.deltoids], expectedRPE: 8, expectedExercises: ["过头推举", "前平举"], expectedSignalCount: 1),
            LabeledCase(text: "手臂日练二头和三头，哑铃弯举加仰卧臂屈伸，RPE 7", expectedPrimary: [.biceps, .triceps], expectedRPE: 7, expectedExercises: ["弯举", "三头臂屈伸"], expectedSignalCount: 0),
            LabeledCase(text: "核心训练：平板支撑和俄式转体，悬垂举腿 3 组，微汗", expectedPrimary: [.abs, .obliques], expectedRPE: 5, expectedExercises: ["平板支撑", "俄式转体/核心", "悬垂举腿"], expectedSignalCount: 0),
            LabeledCase(text: "健腹轮和卷腹强化腹肌，RPE 6", expectedPrimary: [.abs], expectedRPE: 6, expectedExercises: ["卷腹/腹肌轮"], expectedSignalCount: 0),
            LabeledCase(text: "牧师凳弯举配绳索下压，前臂有点紧，RPE 8", expectedPrimary: [.biceps, .triceps], expectedRPE: 8, expectedExercises: ["弯举", "三头臂屈伸"], expectedSignalCount: 1),
            LabeledCase(text: "肩推和后束飞鸟，左肩袖弹响，RPE 7", expectedPrimary: [.deltoids], expectedRPE: 7, expectedExercises: ["过头推举", "后束飞鸟"], expectedSignalCount: 1),
            LabeledCase(text: "斜方肌耸肩 4 组加农夫行走，手腕酸，RPE 8", expectedPrimary: [.trapezius, .forearm], expectedRPE: 8, expectedExercises: ["耸肩", "农夫行走/前臂"], expectedSignalCount: 1),
            LabeledCase(text: "侧平举做 5 组递减力竭，左肩略紧", expectedPrimary: [.deltoids], expectedRPE: 9, expectedExercises: ["侧平举"], expectedSignalCount: 1),
            LabeledCase(text: "腹斜肌侧平板和卷腹，适中完成", expectedPrimary: [.obliques, .abs], expectedRPE: 7, expectedExercises: ["俄式转体/核心", "卷腹/腹肌轮"], expectedSignalCount: 0),
            LabeledCase(text: "颈后臂屈伸加碎颅者强化三头肌，RPE 8", expectedPrimary: [.triceps], expectedRPE: 8, expectedExercises: ["三头臂屈伸"], expectedSignalCount: 0),
            LabeledCase(text: "哑铃推举 4x10，今天不练胸，RPE 7", expectedPrimary: [.deltoids], expectedSecondary: [.triceps, .trapezius], excludedMuscles: [.chest], expectedRPE: 7, expectedExercises: ["哑铃推举"], expectedSignalCount: 0),

            // 45-55: Mixed Upper/Lower, Sports, Negations & Complex Signals
            LabeledCase(text: "上肢推拉：卧推 4 组和引体向上 4 组，RPE 8", expectedPrimary: [.chest, .upperBack, .deltoids], expectedRPE: 8, expectedExercises: ["卧推", "引体向上"], expectedSignalCount: 0),
            LabeledCase(text: "晚上羽毛球单打两局，小腿微紧，左脚踝有点不适，RPE 8", expectedPrimary: [.quadriceps, .calves, .deltoids, .forearm], expectedRPE: 8, expectedExercises: ["羽毛球"], expectedSignalCount: 2),
            LabeledCase(text: "间歇跑 5 公里加平板支撑，小腿酸痛，挺累", expectedPrimary: [.quadriceps, .calves, .hamstring, .abs], expectedRPE: 8, expectedExercises: ["跑步", "平板支撑"], expectedSignalCount: 1),
            LabeledCase(text: "全身分化：深蹲、平板卧推加杠铃划船，RPE 8", expectedPrimary: [.chest, .upperBack, .quadriceps, .gluteal], expectedRPE: 8, expectedExercises: ["深蹲", "杠铃卧推", "杠铃划船"], expectedSignalCount: 0),
            LabeledCase(text: "练胸配练背超级组，夹胸加高位下拉，正常节奏", expectedPrimary: [.chest, .upperBack], expectedRPE: 7, expectedExercises: ["夹胸/飞鸟", "高位下拉"], expectedSignalCount: 0),
            LabeledCase(text: "bench press 4x6 and lat pulldown 4x10, RPE 8", expectedPrimary: [.chest, .upperBack], expectedRPE: 8, expectedExercises: ["卧推", "高位下拉"], expectedSignalCount: 0),
            LabeledCase(text: "rdl 4 sets and calf raise 4 sets, RPE 7", expectedPrimary: [.hamstring, .gluteal, .calves], expectedRPE: 7, expectedExercises: ["罗马尼亚硬拉", "提踵"], expectedSignalCount: 0),
            LabeledCase(text: "高脚杯深蹲 3 组，加悬垂举腿，省去硬拉，轻重量恢复", expectedPrimary: [.quadriceps, .gluteal, .abs], expectedSecondary: [.hamstring, .lowerBack], excludedMuscles: [.chest], expectedRPE: 5, expectedExercises: ["深蹲", "悬垂举腿"], expectedSignalCount: 0),
            LabeledCase(text: "哑铃卧推加侧平举加三头下压，右腕有点紧，RPE 8", expectedPrimary: [.chest, .deltoids, .triceps], expectedRPE: 8, expectedExercises: ["哑铃卧推", "侧平举", "三头臂屈伸"], expectedSignalCount: 1),
            LabeledCase(text: "坐姿划船加二头弯举，右肘发紧，腰部僵硬，RPE 7", expectedPrimary: [.upperBack, .biceps], expectedRPE: 7, expectedExercises: ["划船", "弯举"], expectedSignalCount: 2),
            LabeledCase(text: "羽毛球双打加面拉拉伸肩袖，轻松完成", expectedPrimary: [.quadriceps, .calves, .deltoids, .forearm, .upperBack], expectedRPE: 5, expectedExercises: ["羽毛球", "面拉"], expectedSignalCount: 0),
        ]

        XCTAssertGreaterThanOrEqual(cases.count, 55)

        var primaryHit = 0
        var secondaryAndNegationHit = 0
        var rpeHit = 0
        var exerciseHit = 0
        var signalHit = 0

        for (idx, item) in cases.enumerated() {
            let parsed = ChineseWorkoutLexiconParser.parse(item.text)
            let gotPrimary = Set(parsed.primaryMuscles)
            let gotSecondary = Set(parsed.secondaryMuscles)
            let gotAll = gotPrimary.union(gotSecondary)

            if item.expectedPrimary.isSubset(of: gotAll) && !gotPrimary.isEmpty {
                primaryHit += 1
            } else {
                XCTFail("Case \(idx + 1) primary mismatch: text='\(item.text)' gotPrimary=\(gotPrimary) gotAll=\(gotAll) expected=\(item.expectedPrimary)")
            }

            if item.expectedSecondary.isSubset(of: gotAll) && item.excludedMuscles.isDisjoint(with: gotAll) {
                secondaryAndNegationHit += 1
            } else {
                XCTFail("Case \(idx + 1) secondary/negation mismatch: text='\(item.text)' gotAll=\(gotAll) expectedSecondary=\(item.expectedSecondary) excluded=\(item.excludedMuscles)")
            }

            if parsed.rpe == item.expectedRPE {
                rpeHit += 1
            } else {
                XCTFail("Case \(idx + 1) RPE mismatch: text='\(item.text)' got=\(String(describing: parsed.rpe)) expected=\(String(describing: item.expectedRPE))")
            }

            let gotExercises = Set(parsed.exercises)
            if item.expectedExercises.isSubset(of: gotExercises) {
                exerciseHit += 1
            } else {
                XCTFail("Case \(idx + 1) exercise mismatch: text='\(item.text)' got=\(gotExercises) expected=\(item.expectedExercises)")
            }

            if parsed.bodySignals.count == item.expectedSignalCount {
                signalHit += 1
            } else {
                XCTFail("Case \(idx + 1) bodySignal mismatch: text='\(item.text)' got=\(parsed.bodySignals.count) (\(parsed.bodySignals.map { "\($0.region)\($0.symptom)" })) expected=\(item.expectedSignalCount)")
            }
        }

        let n = Double(cases.count)
        let primaryAcc = Double(primaryHit) / n
        let secondaryAcc = Double(secondaryAndNegationHit) / n
        let rpeAcc = Double(rpeHit) / n
        let exerciseAcc = Double(exerciseHit) / n
        let signalAcc = Double(signalHit) / n
        print(
            String(
                format: "PARSER_ACCURACY_M2: n=%d primary=%.1f%% secondary_negation=%.1f%% rpe=%.1f%% exercises=%.1f%% bodySignals=%.1f%%",
                cases.count,
                primaryAcc * 100,
                secondaryAcc * 100,
                rpeAcc * 100,
                exerciseAcc * 100,
                signalAcc * 100
            )
        )

        XCTAssertGreaterThanOrEqual(primaryAcc, 0.90)
        XCTAssertGreaterThanOrEqual(secondaryAcc, 0.90)
        XCTAssertGreaterThanOrEqual(rpeAcc, 0.90)
        XCTAssertGreaterThanOrEqual(exerciseAcc, 0.90)
        XCTAssertGreaterThanOrEqual(signalAcc, 0.90)
    }
}
