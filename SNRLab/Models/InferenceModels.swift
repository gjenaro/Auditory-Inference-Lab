import Foundation

enum AuditoryInferenceMetricKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case toneReliability
    case speechEfficiency
    case contextUse
    case auditoryRestoration
    case predictionControl
    case adaptation
    case listeningEase

    var id: String { rawValue }

    func displayName(in language: TestLanguage) -> String {
        switch self {
        case .toneReliability:
            return language.text("Tone reliability", "Fiabilidad tonal")
        case .speechEfficiency:
            return language.text("Speech-in-noise efficiency", "Eficiencia de habla con ruido")
        case .contextUse:
            return language.text("Context use", "Uso del contexto")
        case .auditoryRestoration:
            return language.text("Auditory restoration", "Restauración auditiva")
        case .predictionControl:
            return language.text("Prediction control", "Control de predicción")
        case .adaptation:
            return language.text("Adaptation", "Adaptación")
        case .listeningEase:
            return language.text("Listening ease", "Facilidad de escucha")
        }
    }

    var symbol: String {
        switch self {
        case .toneReliability: return "waveform.path.ecg"
        case .speechEfficiency: return "person.wave.2.fill"
        case .contextUse: return "text.bubble.fill"
        case .auditoryRestoration: return "waveform.badge.plus"
        case .predictionControl: return "arrow.triangle.branch"
        case .adaptation: return "chart.line.uptrend.xyaxis"
        case .listeningEase: return "sparkles"
        }
    }
}

struct AuditoryInferenceMetric: Identifiable, Hashable {
    let kind: AuditoryInferenceMetricKind
    /// A bounded, app-internal display score. It is not a clinical norm.
    let score: Double
    let rawValue: Double
    let rawUnit: String
    let evidenceReliability: Double

    var id: String { kind.id }
}

struct AuditoryInferenceProfile: Hashable {
    let metrics: [AuditoryInferenceMetric]
    let completeness: Double
    let evidenceConfidence: Double
    let pureToneDate: Date?
    let speechDate: Date?
    let predictiveDate: Date?

    func metric(_ kind: AuditoryInferenceMetricKind) -> AuditoryInferenceMetric? {
        metrics.first { $0.kind == kind }
    }

    static func derive(
        pureToneTest: BilateralPureToneTest?,
        speechSNR50: Double?,
        speechTrialCount: Int,
        speechDate: Date?,
        predictiveTest: PredictiveListeningTest?
    ) -> AuditoryInferenceProfile {
        var metrics: [AuditoryInferenceMetric] = []
        var protocolReliabilities: [Double] = []

        if let pureToneTest {
            protocolReliabilities.append(bounded(pureToneTest.reliabilityScore))
            metrics.append(AuditoryInferenceMetric(
                kind: .toneReliability,
                score: bounded(pureToneTest.reliabilityScore),
                rawValue: pureToneTest.reliabilityScore,
                rawUnit: "%",
                evidenceReliability: bounded(pureToneTest.reliabilityScore)
            ))
        }

        if let speechSNR50 {
            let speechReliability = bounded(Double(speechTrialCount) / 24 * 100)
            protocolReliabilities.append(speechReliability)
            metrics.append(AuditoryInferenceMetric(
                kind: .speechEfficiency,
                // Lower SNR50 is better. This is an app-relative visualization,
                // deliberately not an age norm or diagnostic boundary.
                score: bounded(65 - speechSNR50 * 4),
                rawValue: speechSNR50,
                rawUnit: "dB SNR50",
                evidenceReliability: speechReliability
            ))
        }

        if let predictiveTest {
            let reliability = bounded(predictiveTest.reliabilityScore)
            protocolReliabilities.append(reliability)
            metrics.append(contentsOf: [
                AuditoryInferenceMetric(
                    kind: .contextUse,
                    score: bounded(50 + predictiveTest.contextBenefit),
                    rawValue: predictiveTest.contextBenefit,
                    rawUnit: "pp",
                    evidenceReliability: reliability
                ),
                AuditoryInferenceMetric(
                    kind: .auditoryRestoration,
                    score: bounded(50 + predictiveTest.restorationBenefit),
                    rawValue: predictiveTest.restorationBenefit,
                    rawUnit: "pp",
                    evidenceReliability: reliability
                ),
                AuditoryInferenceMetric(
                    kind: .predictionControl,
                    score: bounded(100 - predictiveTest.predictionCost),
                    rawValue: predictiveTest.predictionCost,
                    rawUnit: "% intrusions",
                    evidenceReliability: reliability
                ),
                AuditoryInferenceMetric(
                    kind: .adaptation,
                    score: bounded(50 + predictiveTest.adaptationGain),
                    rawValue: predictiveTest.adaptationGain,
                    rawUnit: "pp",
                    evidenceReliability: reliability
                ),
                AuditoryInferenceMetric(
                    kind: .listeningEase,
                    score: bounded((6 - predictiveTest.averageEffort) / 5 * 100),
                    rawValue: predictiveTest.averageEffort,
                    rawUnit: "/5 effort",
                    evidenceReliability: reliability
                )
            ])
        }

        let availableModules = [pureToneTest != nil, speechSNR50 != nil, predictiveTest != nil]
        let completeness = Double(availableModules.filter { $0 }.count) / 3 * 100
        let evidenceConfidence = protocolReliabilities.isEmpty
            ? 0
            : protocolReliabilities.reduce(0, +) / Double(protocolReliabilities.count)

        return AuditoryInferenceProfile(
            metrics: metrics,
            completeness: completeness,
            evidenceConfidence: evidenceConfidence,
            pureToneDate: pureToneTest?.date,
            speechDate: speechDate,
            predictiveDate: predictiveTest?.date
        )
    }

    private static func bounded(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

enum CompensationStrategy: String, CaseIterable, Codable, Identifiable, Hashable {
    case original
    case audiogram
    case speechAware
    case inferenceVerified

    var id: String { rawValue }

    func displayName(in language: TestLanguage) -> String {
        switch self {
        case .original: return language.text("Original", "Original")
        case .audiogram: return language.text("Tone profile", "Perfil tonal")
        case .speechAware: return language.text("Speech-aware", "Adaptado al habla")
        case .inferenceVerified: return language.text("Inference candidate", "Candidato de inferencia")
        }
    }

    func shortDescription(in language: TestLanguage) -> String {
        switch self {
        case .original:
            return language.text("No frequency compensation", "Sin compensación de frecuencia")
        case .audiogram:
            return language.text("Conservative left/right tone-profile filter", "Filtro tonal conservador por oído")
        case .speechAware:
            return language.text("Tone filter with modest speech-band emphasis", "Filtro tonal con énfasis moderado en la banda del habla")
        case .inferenceVerified:
            return language.text("Reliability-weighted experimental candidate", "Candidato experimental ponderado por fiabilidad")
        }
    }

    var symbol: String {
        switch self {
        case .original: return "waveform"
        case .audiogram: return "ear"
        case .speechAware: return "person.wave.2.fill"
        case .inferenceVerified: return "brain.head.profile"
        }
    }
}

struct InferenceCompensationBand: Identifiable, Hashable {
    var id: Double { frequency }
    let frequency: Double
    let leftGainDB: Double
    let rightGainDB: Double
    let leftUncertaintyDB: Double
    let rightUncertaintyDB: Double
    let leftEvidence: Double
    let rightEvidence: Double

    var stereoBand: StereoCompensationBand {
        StereoCompensationBand(
            frequency: frequency,
            leftGainDB: leftGainDB,
            rightGainDB: rightGainDB
        )
    }
}

enum InferenceCompensationDesigner {
    static func bands(
        strategy: CompensationStrategy,
        pureToneTest: BilateralPureToneTest?,
        speechSNR50: Double?,
        predictiveTest: PredictiveListeningTest?,
        maximumBoostDB: Double
    ) -> [InferenceCompensationBand] {
        let maximum = min(20, max(0, maximumBoostDB))
        let base = CompensationDesigner.bands(from: pureToneTest, maximumBoostDB: maximum)

        return base.map { band in
            let leftEvidence = evidence(
                for: .left,
                frequency: band.frequency,
                test: pureToneTest
            )
            let rightEvidence = evidence(
                for: .right,
                frequency: band.frequency,
                test: pureToneTest
            )
            let speechWeight = speechBandWeight(
                frequency: band.frequency,
                speechSNR50: speechSNR50
            )
            let inferenceWeight = inferenceBandWeight(
                frequency: band.frequency,
                predictiveTest: predictiveTest
            )

            let left = adjustedGain(
                base: band.leftGainDB,
                strategy: strategy,
                evidence: leftEvidence,
                speechWeight: speechWeight,
                inferenceWeight: inferenceWeight,
                maximum: maximum
            )
            let right = adjustedGain(
                base: band.rightGainDB,
                strategy: strategy,
                evidence: rightEvidence,
                speechWeight: speechWeight,
                inferenceWeight: inferenceWeight,
                maximum: maximum
            )

            return InferenceCompensationBand(
                frequency: band.frequency,
                leftGainDB: left,
                rightGainDB: right,
                leftUncertaintyDB: strategy == .original
                    ? 0
                    : uncertainty(gain: left, evidence: leftEvidence, maximum: maximum),
                rightUncertaintyDB: strategy == .original
                    ? 0
                    : uncertainty(gain: right, evidence: rightEvidence, maximum: maximum),
                leftEvidence: leftEvidence,
                rightEvidence: rightEvidence
            )
        }
    }

    private static func adjustedGain(
        base: Double,
        strategy: CompensationStrategy,
        evidence: Double,
        speechWeight: Double,
        inferenceWeight: Double,
        maximum: Double
    ) -> Double {
        let value: Double
        switch strategy {
        case .original:
            value = 0
        case .audiogram:
            value = base
        case .speechAware:
            value = base * speechWeight
        case .inferenceVerified:
            // Low-confidence thresholds reduce rather than increase the proposed
            // gain. Cognitive measures only tune candidate strength; they are not
            // treated as proof that equalization can compensate for cognition.
            let reliabilityWeight = 0.55 + 0.45 * evidence
            value = base * speechWeight * inferenceWeight * reliabilityWeight
        }
        return min(maximum, max(0, value))
    }

    private static func speechBandWeight(frequency: Double, speechSNR50: Double?) -> Double {
        guard (1_000...4_000).contains(frequency), let speechSNR50 else { return 1 }
        let challenge = min(1, max(0, (speechSNR50 + 5) / 15))
        return 1 + 0.15 * challenge
    }

    private static func inferenceBandWeight(
        frequency: Double,
        predictiveTest: PredictiveListeningTest?
    ) -> Double {
        guard (1_000...4_000).contains(frequency), let predictiveTest else { return 1 }
        let restorationNeed = min(1, max(0, (20 - predictiveTest.restorationBenefit) / 40))
        let intrusionNeed = min(1, max(0, predictiveTest.predictionCost / 100))
        let reliable = min(1, max(0, predictiveTest.reliabilityScore / 100))
        return 1 + 0.10 * ((restorationNeed + intrusionNeed) / 2) * reliable
    }

    private static func evidence(
        for ear: HearingEar,
        frequency: Double,
        test: BilateralPureToneTest?
    ) -> Double {
        guard let test,
              let threshold = test.threshold(for: ear, frequency: frequency) else { return 0 }

        let criterion = threshold.metAscendingCriterion ? 1.0 : 0.45
        let presentation = min(1, Double(threshold.presentationCount) / 8)
        let reversals = min(1, Double(threshold.reversalCount) / 2)
        let global = test.reliabilityScore / 100
        let repeatability: Double
        if let difference = test.oneKilohertzRepeatDifference(for: ear) {
            repeatability = min(1, max(0, 1 - max(0, difference - 5) / 20))
        } else {
            repeatability = 0.65
        }
        return min(1, max(0,
            criterion * 0.30 +
            presentation * 0.15 +
            reversals * 0.15 +
            global * 0.25 +
            repeatability * 0.15
        ))
    }

    private static func uncertainty(gain: Double, evidence: Double, maximum: Double) -> Double {
        guard maximum > 0 else { return 0 }
        return min(maximum, max(0.35, (1 - evidence) * (1.5 + gain * 0.55)))
    }
}

enum BlindComparisonChoice: String, Codable, Hashable {
    case a
    case b
    case noDifference
}

struct BlindComparisonTrial: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let trackID: String
    let strategyA: CompensationStrategy
    let strategyB: CompensationStrategy
    let choice: BlindComparisonChoice
    let maximumBoostDB: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        trackID: String,
        strategyA: CompensationStrategy,
        strategyB: CompensationStrategy,
        choice: BlindComparisonChoice,
        maximumBoostDB: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trackID = trackID
        self.strategyA = strategyA
        self.strategyB = strategyB
        self.choice = choice
        self.maximumBoostDB = maximumBoostDB
    }

    var preferredStrategy: CompensationStrategy? {
        switch choice {
        case .a: return strategyA
        case .b: return strategyB
        case .noDifference: return nil
        }
    }
}

struct PersonalizationExperiment: Identifiable, Codable, Hashable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    let pureToneTestID: UUID?
    let speechTestID: UUID?
    let predictiveTestID: UUID?
    var trials: [BlindComparisonTrial]

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        pureToneTestID: UUID?,
        speechTestID: UUID?,
        predictiveTestID: UUID?,
        trials: [BlindComparisonTrial] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.pureToneTestID = pureToneTestID
        self.speechTestID = speechTestID
        self.predictiveTestID = predictiveTestID
        self.trials = trials
    }

    mutating func record(_ trial: BlindComparisonTrial) {
        trials.append(trial)
        updatedAt = trial.timestamp
    }

    func wins(for strategy: CompensationStrategy) -> Int {
        trials.filter { $0.preferredStrategy == strategy }.count
    }

    var nonTieCount: Int { trials.filter { $0.choice != .noDifference }.count }

    var recommendedStrategy: CompensationStrategy? {
        guard trials.count >= 6, nonTieCount >= 4 else { return nil }
        let ranked = CompensationStrategy.allCases
            .map { ($0, wins(for: $0)) }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first,
              best.1 >= 3,
              ranked.count < 2 || best.1 > ranked[1].1 else { return nil }
        return best.0
    }

    var recommendationEvidence: Double {
        guard let recommendation = recommendedStrategy else { return 0 }
        let appearances = trials.filter {
            $0.choice != .noDifference &&
            ($0.strategyA == recommendation || $0.strategyB == recommendation)
        }.count
        guard appearances > 0 else { return 0 }
        return Double(wins(for: recommendation)) / Double(appearances) * 100
    }
}
