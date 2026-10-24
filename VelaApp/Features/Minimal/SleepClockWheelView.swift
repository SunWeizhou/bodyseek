import SwiftUI

struct SleepClockWheelView: View {
    let bedtimeHour: Int
    let bedtimeMinute: Int
    let wakeHour: Int
    let wakeMinute: Int
    let targetSleepMinutes: Int

    private var bedtimeAngle: Double {
        VelaMinimalFormatting.sleepDialAngle(hour: bedtimeHour, minute: bedtimeMinute)
    }

    private var wakeAngle: Double {
        VelaMinimalFormatting.sleepDialAngle(hour: wakeHour, minute: wakeMinute)
    }

    private var sleepDurationFraction: Double {
        Double(
            VelaMinimalFormatting.sleepDurationMinutes(
                bedtimeHour: bedtimeHour,
                bedtimeMinute: bedtimeMinute,
                wakeHour: wakeHour,
                wakeMinute: wakeMinute
            )
        ) / Double(24 * 60)
    }
    
    var body: some View {
        ZStack {
            // Dial background
            Circle()
                .fill(VelaTheme.rhythmCanvasRaised)
                .frame(width: 170, height: 170)
                .overlay(
                    Circle()
                        .stroke(VelaTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                )
            
            // Hour markings around the circle (12am, 6am, 12pm, 6pm)
            dialHourText("12am", angle: -90, radius: 68)
            dialHourText("6am", angle: 0, radius: 68)
            dialHourText("12pm", angle: 90, radius: 68)
            dialHourText("6pm", angle: 180, radius: 68)
            
            // Tiny tick dots
            ForEach(0..<12) { idx in
                let deg = Double(idx) * 30.0 - 90.0
                let r = 76.0
                Circle()
                    .fill(VelaTheme.hairline)
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: r * cos(deg * .pi / 180), y: r * sin(deg * .pi / 180))
            }

            // Sleep Duration Indicator Arc
            Circle()
                .trim(from: 0.0, to: sleepDurationFraction)
                .stroke(
                    VelaTheme.rhythmInk,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(bedtimeAngle - 90.0))

            // Center icons (moon and sun)
            VStack(spacing: 16) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(VelaTheme.rhythmInk)
                
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .offset(y: -4)

            // Bedtime Indicator Icon overlay (bed)
            dialIndicatorPill(icon: "bed.double.fill", color: VelaTheme.rhythmInk)
                .offset(x: 70 * cos((bedtimeAngle - 90.0) * .pi / 180), y: 70 * sin((bedtimeAngle - 90.0) * .pi / 180))
            
            // Wake Indicator Icon overlay (clock)
            dialIndicatorPill(icon: "alarm.fill", color: VelaTheme.rhythmInk)
                .offset(x: 70 * cos((wakeAngle - 90.0) * .pi / 180), y: 70 * sin((wakeAngle - 90.0) * .pi / 180))
        }
        .overlay(alignment: .bottom) {
            Text("今晚睡眠目标: \(VelaMinimalFormatting.duration(minutes: targetSleepMinutes))")
                .font(VelaTheme.caption2())
                .fontWeight(.bold)
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .offset(y: 12)
        }
        // VoiceOver 组合摘要（此前只读得到散落的 12am/6am 装饰文本）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let duration = VelaMinimalFormatting.duration(
            minutes: VelaMinimalFormatting.sleepDurationMinutes(
                bedtimeHour: bedtimeHour,
                bedtimeMinute: bedtimeMinute,
                wakeHour: wakeHour,
                wakeMinute: wakeMinute
            )
        )
        return String(
            format: "就寝 %02d:%02d，起床 %02d:%02d，睡眠 %@；目标 %@",
            bedtimeHour, bedtimeMinute, wakeHour, wakeMinute,
            duration, VelaMinimalFormatting.duration(minutes: targetSleepMinutes)
        )
    }
    
    private func dialHourText(_ label: String, angle: Double, radius: Double) -> some View {
        Text(label)
            .font(VelaTheme.caption2())
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
            .position(x: 85 + radius * cos(angle * .pi / 180), y: 85 + radius * sin(angle * .pi / 180))
    }
    
    private func dialIndicatorPill(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(VelaTheme.rhythmDeepOn)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color))
    }
}
