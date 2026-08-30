import Foundation

// Minimal production-compatible definitions let the pure inference model run as
// a command-line deterministic check without loading the iOS audio engine.
struct StereoCompensationBand: Identifiable, Hashable {
    var id: Double { frequency }
    let frequency: Double
    let leftGainDB: Double
    let rightGainDB: Double
}

enum CompensationDesigner {
    static let frequencies = [250.0, 500.0, 1_000.0, 2_000.0, 3_000.0, 4_000.0, 6_000.0, 8_000.0]

    static func bands(
        from test: BilateralPureToneTest?,
        maximumBoostDB: Double
    ) -> [StereoCompensationBand] {
        guard let test else {
            return frequencies.map { .init(frequency: $0, leftGainDB: 0, rightGainDB: 0) }
        }
        return frequencies.map { frequency in
            let left = test.threshold(for: .left, frequency: frequency)?.finalRelativeThreshold ?? 0
            let right = test.threshold(for: .right, frequency: frequency)?.finalRelativeThreshold ?? 0
            return .init(
                frequency: frequency,
                leftGainDB: min(maximumBoostDB, max(0, (left - 10) * 0.5)),
                rightGainDB: min(maximumBoostDB, max(0, (right - 10) * 0.5))
            )
        }
    }
}

@main
enum InferenceLogicCheck {
    static func main() {
        let test = makeToneTest()
        let profile = AuditoryInferenceProfile.derive(
            pureToneTest: test,
            speechSNR50: 2,
            speechTrialCount: 24,
            speechDate: Date(timeIntervalSince1970: 10),
            predictiveTest: nil
        )
        precondition(profile.completeness > 66 && profile.completeness < 67)
        precondition(profile.metrics.count == 2)

        let original = InferenceCompensationDesigner.bands(
            strategy: .original,
            pureToneTest: test,
            speechSNR50: 2,
            predictiveTest: nil,
            maximumBoostDB: 6
        )
        precondition(original.allSatisfy {
            $0.leftGainDB == 0 && $0.rightGainDB == 0 &&
            $0.leftUncertaintyDB == 0 && $0.rightUncertaintyDB == 0
        })

        let candidate = InferenceCompensationDesigner.bands(
            strategy: .inferenceVerified,
            pureToneTest: test,
            speechSNR50: 2,
            predictiveTest: nil,
            maximumBoostDB: 6
        )
        precondition(candidate.count == 8)
        precondition(candidate.allSatisfy {
            (0...6).contains($0.leftGainDB) &&
            (0...6).contains($0.rightGainDB) &&
            (0...1).contains($0.leftEvidence) &&
            (0...1).contains($0.rightEvidence)
        })

        var experiment = PersonalizationExperiment(
            pureToneTestID: test.id,
            speechTestID: nil,
            predictiveTestID: nil
        )
        let outcomes: [(CompensationStrategy, CompensationStrategy, BlindComparisonChoice)] = [
            (.original, .audiogram, .a),
            (.original, .speechAware, .a),
            (.original, .inferenceVerified, .a),
            (.audiogram, .speechAware, .a),
            (.audiogram, .inferenceVerified, .a),
            (.speechAware, .inferenceVerified, .a)
        ]
        for outcome in outcomes {
            experiment.record(BlindComparisonTrial(
                trackID: "check",
                strategyA: outcome.0,
                strategyB: outcome.1,
                choice: outcome.2,
                maximumBoostDB: 6
            ))
        }
        precondition(experiment.recommendedStrategy == .original)
        precondition(experiment.recommendationEvidence == 100)

        let encoded = try! JSONEncoder().encode(experiment)
        let decoded = try! JSONDecoder().decode(PersonalizationExperiment.self, from: encoded)
        precondition(decoded == experiment)
        print("Inference logic checks passed")
    }

    private static func makeToneTest() -> BilateralPureToneTest {
        let left = [10.0, 10, 15, 20, 25, 20, 15, 10]
        let right = [10.0, 15, 20, 25, 20, 15, 10, 10]
        var results: [PureToneThresholdResult] = []

        for (index, frequency) in CompensationDesigner.frequencies.enumerated() {
            for (ear, levels) in [(HearingEar.left, left), (HearingEar.right, right)] {
                let trials = [
                    PureToneTrial(
                        frequency: frequency,
                        ear: ear,
                        stimulusLevel: levels[index],
                        heard: true,
                        direction: .ascending,
                        responseTime: 0.8,
                        isCatchTrial: false
                    ),
                    PureToneTrial(
                        frequency: frequency,
                        ear: ear,
                        stimulusLevel: levels[index],
                        heard: true,
                        direction: .ascending,
                        responseTime: 0.7,
                        isCatchTrial: false
                    )
                ]
                results.append(PureToneThresholdResult(
                    frequency: frequency,
                    ear: ear,
                    finalRelativeThreshold: levels[index],
                    trials: trials,
                    reversalCount: 2
                ))
            }
        }
        return BilateralPureToneTest(
            name: "Deterministic check",
            results: results,
            ambientNoiseDBFS: -60,
            outputRouteName: "Test stereo route",
            outputChannelCount: 2,
            airPodsSetupConfirmed: false,
            supportedHeadsetSetupConfirmed: true
        )
    }
}
