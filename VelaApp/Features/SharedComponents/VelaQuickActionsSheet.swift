import SwiftUI
import SwiftData
import UIKit
@preconcurrency import AVFoundation

// MARK: - PlusActionSheet — Bevel Replica Quick Actions
// 3×3 circle buttons grid × Dual-eye AI Mascot center × Bottom circle cancel button

struct PlusActionSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView { actions }
            .scrollBounceBehavior(.basedOnSize)
            .background(VelaTheme.bg)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize
                ? [.large]
                : [.height(VelaFeatureFlags.nutritionEnabled ? 440 : 330), .large])
    }

    private var actions: some View {
        VStack(spacing: VelaTheme.space5) {
            // Spacer to replace deleted hint capsule and keep correct layout margin
            Spacer().frame(height: VelaTheme.space4)
            
            // 2. 3×3 Grid
            LazyVGrid(
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.adaptive(minimum: 130), spacing: 14)]
                    : Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: 16
            ) {
                if VelaFeatureFlags.nutritionEnabled {
                    // Row 1 — Nutrition quick actions
                    circleActionButton(icon: "square.and.pencil", label: "描述食物") {
                        deferAction(.coach("描述我今天吃的中餐..."))
                    }

                    circleActionButton(icon: "photo.badge.plus", label: "导入食物") {
                        deferAction(.foodScanner("library"))
                    }

                    circleActionButton(icon: "camera.fill", label: "拍摄食物") {
                        deferAction(.foodScanner("camera"))
                    }

                    // Row 2
                    circleActionButton(icon: "barcode.viewfinder", label: "扫描食物") {
                        deferAction(.foodScanner("barcode"))
                    }

                    // Center: Vela AI Mascot
                    mascotCenterButton(label: "Coach") {
                        deferAction(.coach(nil))
                    }

                    circleActionButton(icon: "book.pages.fill", label: "手记") {
                        deferAction(.journal)
                    }

                    // Row 3
                    circleActionButton(icon: "wand.and.stars", label: "智能处方") {
                        deferAction(.coach("帮我根据今日状态生成一份运动健康处方模板"))
                    }

                    circleActionButton(icon: "list.bullet.clipboard.fill", label: "查看模板") {
                        deferAction(.coach("我有哪些已保存的运动与习惯处方模版？"))
                    }

                    circleActionButton(icon: "figure.run", label: "记录活动") {
                        deferAction(.workoutLog)
                    }
                } else {
                    // 2×3 Balanced Quick Actions Grid (without nutrition)
                    // Row 1: Core Logging Actions
                    circleActionButton(icon: "figure.run", label: "记录活动") {
                        deferAction(.workoutLog)
                    }

                    circleActionButton(icon: "scalemass", label: "记录体重") {
                        deferAction(.weightLog)
                    }

                    circleActionButton(icon: "book.pages.fill", label: "手记") {
                        deferAction(.journal)
                    }

                    // Row 2: Intelligence & Coach Actions (Coach in Center)
                    circleActionButton(icon: "wand.and.stars", label: "智能处方") {
                        deferAction(.coach("帮我根据今日状态生成一份运动健康处方模板"))
                    }

                    mascotCenterButton(label: "Coach") {
                        deferAction(.coach(nil))
                    }

                    circleActionButton(icon: "list.bullet.clipboard.fill", label: "查看模板") {
                        deferAction(.coach("我有哪些已保存的运动与习惯处方模版？"))
                    }
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            
            // Close stays next to the grid instead of the bottom of a half-empty sheet.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VelaTheme.fg)
                    .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                    .background(Circle().fill(VelaTheme.cardBg))
                    .overlay(Circle().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
            }
            .buttonStyle(.plain)
            .padding(.bottom, VelaTheme.space3)
            .accessibilityLabel("关闭")
        }
        .frame(maxWidth: .infinity)
        .background(VelaTheme.bg) // Warm canvas base
    }

    private func deferAction(_ action: VelaAppState.DeferredQuickAction) {
        VelaAppState.shared.deferQuickActionUntilSheetDismisses(action)
        dismiss()
    }

    // MARK: - Standard Circular Action Button
    private func circleActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(VelaTheme.surfaceFloating)
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(VelaTheme.fg)
                }
                
                Text(label)
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.cardPress)
    }

    // MARK: - Center Mascot Sparkles Button
    private func mascotCenterButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: 48, height: 48)
                    
                    AlpacaView(strokeColor: VelaTheme.rhythmDeepOn)
                        .offset(y: -1)
                }
                
                Text(label)
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alpaca Vector Graphic (羊驼简笔画)

struct AlpacaShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Body back & start
        path.move(to: CGPoint(x: w * 0.40, y: h * 0.70))
        
        // Long neck up
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.35))
        
        // Left Ear
        path.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.15), control: CGPoint(x: w * 0.33, y: h * 0.25))
        path.addQuadCurve(to: CGPoint(x: w * 0.45, y: h * 0.30), control: CGPoint(x: w * 0.42, y: h * 0.20))
        
        // Right Ear
        path.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.12), control: CGPoint(x: w * 0.46, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.54, y: h * 0.32), control: CGPoint(x: w * 0.54, y: h * 0.20))
        
        // Head / Forehead
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.35))
        
        // Muzzle / Nose
        path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.40), control: CGPoint(x: w * 0.71, y: h * 0.37))
        // Mouth / Chin
        path.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.45), control: CGPoint(x: w * 0.68, y: h * 0.45))
        
        // Neck front
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.70))
        
        // Fluffy chest curve
        path.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.85), control: CGPoint(x: w * 0.64, y: h * 0.80))
        // Fluffy bottom curve
        path.addQuadCurve(to: CGPoint(x: w * 0.28, y: h * 0.85), control: CGPoint(x: w * 0.48, y: h * 0.90))
        // Back curve
        path.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.70), control: CGPoint(x: w * 0.26, y: h * 0.78))
        
        return path
    }
}

struct AlpacaView: View {
    var strokeColor: Color = VelaTheme.rhythmDeepOn
    var size: CGFloat = 28
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            AlpacaShape()
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            
            // Eye
            Circle()
                .fill(strokeColor)
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(x: size * 0.18, y: -size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

// ==========================================
// MARK: - ACTION SUBVIEWS IMPLEMENTATIONS
// ==========================================

// 1. Workout Activity Logger View (Saves to SwiftData to update heatmaps and strain)
