import Foundation
import SwiftUI

struct NutritionOverviewModel: Equatable {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fiber: Int
    let score: Int?
    let qualityScore: Int?
    let coverageLabel: String

    static func build(
        records: [FoodLogRecord],
        calorieTarget: Int,
        proteinTarget: Int,
        fiberTarget: Int
    ) -> NutritionOverviewModel {
        let calories = records.reduce(0) { $0 + $1.totalCalories }
        let protein = records.reduce(0) { $0 + $1.proteinGrams }
        let carbs = records.reduce(0) { $0 + $1.carbsGrams }
        let fat = records.reduce(0) { $0 + $1.fatGrams }
        let fiber = records.reduce(0) { $0 + $1.fiberGrams }
        guard !records.isEmpty else {
            return NutritionOverviewModel(
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                fiber: 0,
                score: nil,
                qualityScore: nil,
                coverageLabel: "未记录"
            )
        }

        let calorieRatio = Double(calories) / Double(max(calorieTarget, 1))
        let calorieScore = max(0, 100 - abs(calorieRatio - 0.9) * 110)
        let proteinScore = min(Double(protein) / Double(max(proteinTarget, 1)), 1) * 100
        let fiberScore = min(Double(fiber) / Double(max(fiberTarget, 1)), 1) * 100
        let qualityScores = records.compactMap { record -> Double? in
            switch record.healthScore.uppercased() {
            case "A": 100
            case "B": 85
            case "C": 70
            case "D": 55
            case "E": 40
            default: nil
            }
        }
        let qualityScore = qualityScores.isEmpty ? nil : qualityScores.reduce(0, +) / Double(qualityScores.count)
        var weightedScore = calorieScore * 0.30 + proteinScore * 0.30 + fiberScore * 0.20
        var availableWeight = 0.80
        if let qualityScore {
            weightedScore += qualityScore * 0.20
            availableWeight += 0.20
        }
        let rawScore = (weightedScore / availableWeight).rounded()
        let score = Int(min(100, max(0, rawScore)))
        return NutritionOverviewModel(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            score: score,
            qualityScore: qualityScore.map { Int($0.rounded()) },
            coverageLabel: records.count >= 3 ? "较完整" : "部分记录"
        )
    }
}

struct NutritionRecordEdit: Equatable {
    var mealName: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fiber: Int
    var healthScore: String

    func normalized() -> NutritionRecordEdit {
        NutritionRecordEdit(
            mealName: mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "一餐" : mealName.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: min(10_000, max(0, calories)),
            protein: min(1_000, max(0, protein)),
            carbs: min(1_000, max(0, carbs)),
            fat: min(1_000, max(0, fat)),
            fiber: min(200, max(0, fiber)),
            healthScore: ["A", "B", "C", "D", "E"].contains(healthScore.uppercased()) ? healthScore.uppercased() : ""
        )
    }
}

struct NutritionRecipeIngredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: String
}

struct NutritionRecipe: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var servings: Int
    var ingredients: [NutritionRecipeIngredient]
    var createdAt = Date()
}

struct NutritionMealPlanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var recipeID: UUID
    var scheduledDate: Date
}

struct NutritionFoodCartItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var sourceRecipeID: UUID?
    var isChecked = false
}

enum NutritionPlanningStore {
    static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func recipe(from record: FoodLogRecord) -> NutritionRecipe {
        let ingredients: [NutritionRecipeIngredient]
        if record.foods.isEmpty {
            ingredients = [NutritionRecipeIngredient(name: record.mealName, amount: "1 份")]
        } else {
            ingredients = record.foods.map {
                NutritionRecipeIngredient(name: $0.name, amount: $0.portion)
            }
        }
        return NutritionRecipe(
            name: record.mealName,
            servings: 1,
            ingredients: ingredients
        )
    }

    static func cartItems(from recipe: NutritionRecipe) -> [NutritionFoodCartItem] {
        recipe.ingredients.map {
            NutritionFoodCartItem(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceRecipeID: recipe.id
            )
        }.filter { !$0.name.isEmpty }
    }
}

enum NutritionRecipeImportParser {
    static func parse(_ text: String) -> NutritionRecipe? {
        let lines = text.components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
        guard let name = lines.first, lines.count >= 2 else { return nil }
        let ingredients = lines.dropFirst().compactMap { line -> NutritionRecipeIngredient? in
            let parts: [String]
            if line.contains("|") {
                parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            } else if line.contains("\t") {
                parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            } else {
                parts = [line]
            }
            let ingredientName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ingredientName.isEmpty else { return nil }
            let amount = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return NutritionRecipeIngredient(name: ingredientName, amount: amount)
        }
        guard !ingredients.isEmpty else { return nil }
        return NutritionRecipe(name: name, servings: 1, ingredients: ingredients)
    }

    private static func cleanLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
    }
}
