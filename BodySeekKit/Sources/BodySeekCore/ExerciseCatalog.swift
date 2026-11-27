import Foundation

/// Curated bilingual exercise library grounded in `free-exercise-db` taxonomy
/// and mapped 1:1 to `MuscleMap` anatomical regions.
public enum ExerciseCatalog {
    public static let all: [ExerciseDefinition] = [
        // Chest & Push
        ExerciseDefinition(
            id: "barbell-bench-press",
            name: "杠铃平板卧推",
            englishName: "Barbell Bench Press",
            category: .strength,
            equipment: "杠铃",
            primaryMuscles: [.chest],
            secondaryMuscles: [.deltoids, .triceps],
            instructions: "双肩后收下沉贴紧卧推凳，杠铃下放至下胸线位置后发力推起，避免耸肩。"
        ),
        ExerciseDefinition(
            id: "incline-dumbbell-press",
            name: "上斜哑铃卧推",
            englishName: "Incline Dumbbell Press",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.chest],
            secondaryMuscles: [.deltoids, .triceps],
            instructions: "凳面调至 30°，手肘与躯干保持约 45° 夹角，控制离心下放 2 秒。"
        ),
        ExerciseDefinition(
            id: "cable-chest-fly",
            name: "绳索夹胸",
            englishName: "Cable Chest Fly",
            category: .strength,
            equipment: "绳索",
            primaryMuscles: [.chest],
            secondaryMuscles: [.deltoids],
            instructions: "微微前倾保持微屈肘，体会胸大肌中缝向内挤压收缩。"
        ),
        ExerciseDefinition(
            id: "overhead-shoulder-press",
            name: "站姿/坐姿哑铃推举",
            englishName: "Dumbbell Overhead Press",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.deltoids],
            secondaryMuscles: [.triceps, .trapezius],
            instructions: "核心收紧防止腰椎反弓，哑铃在头顶微前侧轨迹推起。"
        ),
        ExerciseDefinition(
            id: "lateral-raise",
            name: "哑铃侧平举",
            englishName: "Dumbbell Lateral Raise",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.deltoids],
            secondaryMuscles: [.trapezius],
            instructions: "肩胛下沉，向斜前方 30° 抬起至与肩同高即可，避免借力甩动。"
        ),
        ExerciseDefinition(
            id: "triceps-rope-pushdown",
            name: "绳索三头下压",
            englishName: "Triceps Rope Pushdown",
            category: .strength,
            equipment: "绳索",
            primaryMuscles: [.triceps],
            secondaryMuscles: [],
            instructions: "大臂紧贴体侧固定，下压底部向两侧掰开绳索充分收缩三头。"
        ),

        // Back & Pull
        ExerciseDefinition(
            id: "lat-pulldown",
            name: "宽握高位下拉",
            englishName: "Wide-Grip Lat Pulldown",
            category: .strength,
            equipment: "固定器械",
            primaryMuscles: [.upperBack],
            secondaryMuscles: [.biceps, .trapezius],
            instructions: "先沉肩再拉肘，将横杆拉至锁骨上胸位置，控制还原。"
        ),
        ExerciseDefinition(
            id: "seated-cable-row",
            name: "坐姿绳索划船",
            englishName: "Seated Cable Row",
            category: .strength,
            equipment: "绳索",
            primaryMuscles: [.upperBack],
            secondaryMuscles: [.biceps, .lowerBack],
            instructions: "保持脊柱中立，手肘贴近躯干向后拉至下腹，肩胛骨向后收紧。"
        ),
        ExerciseDefinition(
            id: "one-arm-dumbbell-row",
            name: "单臂哑铃划船",
            englishName: "One-Arm Dumbbell Row",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.upperBack],
            secondaryMuscles: [.biceps, .deltoids],
            instructions: "同侧手撑凳稳定骨盆，向髋部方向弧线提拉哑铃，聚焦背阔外侧。"
        ),
        ExerciseDefinition(
            id: "face-pull",
            name: "绳索面拉",
            englishName: "Face Pull",
            category: .strength,
            equipment: "绳索",
            primaryMuscles: [.deltoids, .upperBack],
            secondaryMuscles: [.trapezius],
            instructions: "大拇指朝后将绳索拉向眉心两侧，重点强化三角肌后束与肩袖稳定。"
        ),
        ExerciseDefinition(
            id: "barbell-bicep-curl",
            name: "曲杆/哑铃弯举",
            englishName: "Dumbbell Bicep Curl",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearm],
            instructions: "肘关节锁定在体侧不前摆，顶峰停顿 1 秒后再缓慢下放。"
        ),

        // Legs & Posterior Chain
        ExerciseDefinition(
            id: "barbell-back-squat",
            name: "杠铃高脚杯/深蹲",
            englishName: "Barbell Back Squat",
            category: .strength,
            equipment: "杠铃",
            primaryMuscles: [.quadriceps, .gluteal],
            secondaryMuscles: [.lowerBack, .abs],
            instructions: "吸气腹压稳固，髋膝同步屈伸蹲至大腿平行地面后垂直起身。"
        ),
        ExerciseDefinition(
            id: "romanian-deadlift",
            name: "罗马尼亚硬拉",
            englishName: "Romanian Deadlift",
            category: .strength,
            equipment: "杠铃/哑铃",
            primaryMuscles: [.hamstring, .gluteal],
            secondaryMuscles: [.lowerBack, .forearm],
            instructions: "保持脊柱直线与微屈膝，臀部向后折叠推至大腿后侧明显牵拉后发力蹬地。"
        ),
        ExerciseDefinition(
            id: "bulgarian-split-squat",
            name: "保加利亚分腿蹲",
            englishName: "Bulgarian Split Squat",
            category: .strength,
            equipment: "哑铃",
            primaryMuscles: [.quadriceps, .gluteal],
            secondaryMuscles: [.hamstring],
            instructions: "前脚全掌踩实，躯干微前倾降低后膝至近地面再以臀腿推起。"
        ),
        ExerciseDefinition(
            id: "leg-press",
            name: "坐姿腿举",
            englishName: "Leg Press",
            category: .strength,
            equipment: "固定器械",
            primaryMuscles: [.quadriceps],
            secondaryMuscles: [.gluteal, .hamstring],
            instructions: "下背稳贴靠背不卷曲，双脚踩中踏板控制下放与蹬伸（不锁死膝关节）。"
        ),
        ExerciseDefinition(
            id: "standing-calf-raise",
            name: "提踵",
            englishName: "Standing Calf Raise",
            category: .strength,
            equipment: "自重/哑铃",
            primaryMuscles: [.calves],
            secondaryMuscles: [],
            instructions: "底部充分拉伸跟腱 1 秒，顶峰用力垫脚停顿后慢放。"
        ),

        // Core & Cardio & Mobility
        ExerciseDefinition(
            id: "hanging-leg-raise",
            name: "悬垂/仰卧举腿",
            englishName: "Leg Raise",
            category: .strength,
            equipment: "自重",
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques],
            instructions: "骨盆后卷发力抬腿而非靠惯性甩腿，缓慢还原控制离心。"
        ),
        ExerciseDefinition(
            id: "zone2-easy-run",
            name: "Zone 2 轻松跑/有氧骑行",
            englishName: "Zone 2 Aerobic Base",
            category: .cardio,
            equipment: "有氧",
            primaryMuscles: [.quadriceps, .calves],
            secondaryMuscles: [.hamstring, .gluteal],
            instructions: "心率保持在最大心率 60–72%（可完整对话节奏），重点打牢线粒体与有氧恢复基底。"
        ),
        ExerciseDefinition(
            id: "thoracic-hip-mobility",
            name: "胸椎开合与髋部拉伸流",
            englishName: "Thoracic & Hip Mobility",
            category: .mobility,
            equipment: "瑜伽垫",
            primaryMuscles: [.lowerBack, .gluteal],
            secondaryMuscles: [.upperBack, .obliques],
            instructions: "配合深长腹式呼吸完成猫牛式、90/90 转髋与侧卧胸椎旋转，降低交感神经张力。"
        ),
    ]

    public static func find(id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }

    public static func exercises(for muscle: BodyRegionMuscle) -> [ExerciseDefinition] {
        all.filter { $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle) }
    }

    public static let defaultTemplates: [WorkoutTemplate] = [
        WorkoutTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,
            title: "上肢推力 · 胸肩三头",
            subtitle: "复合推举主项 + 三角肌中束与三头孤立",
            focusTag: "力量分化",
            estimatedMinutes: 45,
            exercises: [
                PlannedExerciseItem(exerciseID: "barbell-bench-press", targetSets: 4, targetReps: 8, targetWeightKg: 60, restSeconds: 120),
                PlannedExerciseItem(exerciseID: "incline-dumbbell-press", targetSets: 3, targetReps: 10, targetWeightKg: 20, restSeconds: 90),
                PlannedExerciseItem(exerciseID: "overhead-shoulder-press", targetSets: 3, targetReps: 10, targetWeightKg: 16, restSeconds: 90),
                PlannedExerciseItem(exerciseID: "lateral-raise", targetSets: 3, targetReps: 15, targetWeightKg: 8, restSeconds: 60),
                PlannedExerciseItem(exerciseID: "triceps-rope-pushdown", targetSets: 3, targetReps: 12, targetWeightKg: 22, restSeconds: 60),
            ]
        ),
        WorkoutTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111102")!,
            title: "上肢拉力 · 背阔与二头",
            subtitle: "垂直下拉 + 水平划船构建背部厚度",
            focusTag: "力量分化",
            estimatedMinutes: 42,
            exercises: [
                PlannedExerciseItem(exerciseID: "lat-pulldown", targetSets: 4, targetReps: 10, targetWeightKg: 50, restSeconds: 90),
                PlannedExerciseItem(exerciseID: "seated-cable-row", targetSets: 3, targetReps: 10, targetWeightKg: 45, restSeconds: 90),
                PlannedExerciseItem(exerciseID: "one-arm-dumbbell-row", targetSets: 3, targetReps: 10, targetWeightKg: 22, restSeconds: 75),
                PlannedExerciseItem(exerciseID: "face-pull", targetSets: 3, targetReps: 15, targetWeightKg: 18, restSeconds: 60),
                PlannedExerciseItem(exerciseID: "barbell-bicep-curl", targetSets: 3, targetReps: 12, targetWeightKg: 12, restSeconds: 60),
            ]
        ),
        WorkoutTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111103")!,
            title: "下肢与后链强化",
            subtitle: "深蹲 + 罗马尼亚硬拉兼顾前侧与后链",
            focusTag: "下肢力量",
            estimatedMinutes: 48,
            exercises: [
                PlannedExerciseItem(exerciseID: "barbell-back-squat", targetSets: 4, targetReps: 6, targetWeightKg: 70, restSeconds: 150),
                PlannedExerciseItem(exerciseID: "romanian-deadlift", targetSets: 3, targetReps: 8, targetWeightKg: 60, restSeconds: 120),
                PlannedExerciseItem(exerciseID: "bulgarian-split-squat", targetSets: 3, targetReps: 10, targetWeightKg: 14, restSeconds: 90),
                PlannedExerciseItem(exerciseID: "standing-calf-raise", targetSets: 3, targetReps: 15, targetWeightKg: 30, restSeconds: 60),
                PlannedExerciseItem(exerciseID: "hanging-leg-raise", targetSets: 3, targetReps: 12, targetWeightKg: 0, restSeconds: 60),
            ]
        ),
        WorkoutTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111104")!,
            title: "主动恢复 · 活动度与呼吸",
            subtitle: "低负荷拉伸释放疲劳，改善今晚 HRV",
            focusTag: "恢复日",
            estimatedMinutes: 25,
            exercises: [
                PlannedExerciseItem(exerciseID: "zone2-easy-run", targetSets: 1, targetReps: 20, targetWeightKg: 0, restSeconds: 30),
                PlannedExerciseItem(exerciseID: "thoracic-hip-mobility", targetSets: 3, targetReps: 8, targetWeightKg: 0, restSeconds: 45),
            ]
        ),
    ]
}
