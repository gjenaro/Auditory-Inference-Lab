import Foundation

@main
struct SpeechComparisonLogicCheck {
    static func main() {
        for language in TestLanguage.allCases {
            let candidates = Array(TestSentence.bank(for: language).prefix(36))
            guard let plan = SpeechComparisonPlanner.makePlan(
                candidates: candidates,
                language: language,
                trialsPerCondition: 12,
                seed: 20_260_830
            ) else {
                fatalError("Planner failed for \(language.rawValue)")
            }
            precondition(plan.trials.count == 24)
            precondition(plan.trials(for: .standard).count == 12)
            precondition(plan.trials(for: .audiogramEQ).count == 12)
            precondition(Set(plan.trials.map(\.sentence)).count == 24)
            precondition(plan.blockOrder.count == 2)
            precondition(Set(plan.blockOrder).count == 2)

            let completed = plan.trials.map { trial in
                SpeechComparisonTrial(
                    pairIndex: trial.pairIndex,
                    condition: trial.condition,
                    sentence: trial.sentence,
                    response: trial.sentence,
                    score: trial.condition == .audiogramEQ ? 0.8 : 0.7,
                    responseTime: 2,
                    playbackCount: 1,
                    complexity: trial.complexity
                )
            }
            let result = SpeechEQComparisonTest(
                id: UUID(),
                name: "Logic check",
                date: Date(),
                language: language,
                voiceProfile: .woman,
                resolvedVoiceName: nil,
                noise: .restaurant,
                snrDB: 3,
                pureToneTestID: UUID(),
                pureToneTestName: "Audiogram",
                pureToneRouteName: "Headphones",
                maximumBoostDB: 6,
                bands: [],
                blockOrder: plan.blockOrder,
                planSeed: plan.seed,
                trials: completed
            )
            precondition(abs(result.differencePercentagePoints - 10) < 0.001)
            precondition(abs(result.wordCountDifference) <= 0.25)
            print("\(language.rawValue): 24 unique sentences; word Δ \(result.wordCountDifference); max shared content \(result.maximumSharedContentWordsPerPair)")
        }
    }
}
