import Foundation

enum SpeechComparisonCondition: String, Codable, Hashable, Identifiable {
    case standard
    case audiogramEQ

    var id: String { rawValue }

    func displayName(in language: TestLanguage) -> String {
        switch self {
        case .standard: return language.text("Standard", "Estándar")
        case .audiogramEQ: return language.text("Audiogram EQ", "EQ del audiograma")
        }
    }
}

struct SpeechSentenceComplexity: Codable, Hashable {
    let wordCount: Int
    let letterCount: Int
    let vowelGroupCount: Int
    let contentWords: Set<String>

    static func measure(_ text: String, language: TestLanguage) -> SpeechSentenceComplexity {
        let words = normalizedWords(in: text)
        let stopWords: Set<String> = language == .english
            ? ["a", "an", "and", "at", "before", "beside", "into", "near", "of", "on", "the", "to", "toward", "under"]
            : ["a", "al", "antes", "cerca", "con", "de", "del", "despues", "el", "en", "hacia", "la", "las", "los", "por", "un", "una", "y"]
        let contentWords = Set(words.filter { !stopWords.contains($0) })
        let letters = words.reduce(0) { $0 + $1.count }
        let vowels = Set("aeiouyáéíóúü")
        let vowelGroups = words.reduce(0) { total, word in
            var count = 0
            var priorWasVowel = false
            for character in word {
                let isVowel = vowels.contains(character)
                if isVowel && !priorWasVowel { count += 1 }
                priorWasVowel = isVowel
            }
            return total + count
        }
        return SpeechSentenceComplexity(
            wordCount: words.count,
            letterCount: letters,
            vowelGroupCount: vowelGroups,
            contentWords: contentWords
        )
    }

    private static func normalizedWords(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }
}

struct PlannedSpeechComparisonTrial: Identifiable, Hashable {
    let id: UUID
    let pairIndex: Int
    let condition: SpeechComparisonCondition
    let sentence: String
    let complexity: SpeechSentenceComplexity

    init(
        id: UUID = UUID(),
        pairIndex: Int,
        condition: SpeechComparisonCondition,
        sentence: String,
        complexity: SpeechSentenceComplexity
    ) {
        self.id = id
        self.pairIndex = pairIndex
        self.condition = condition
        self.sentence = sentence
        self.complexity = complexity
    }
}

struct SpeechComparisonPlan: Hashable {
    let seed: UInt64
    let blockOrder: [SpeechComparisonCondition]
    let trials: [PlannedSpeechComparisonTrial]

    func trials(for condition: SpeechComparisonCondition) -> [PlannedSpeechComparisonTrial] {
        trials.filter { $0.condition == condition }
    }
}

struct SpeechComparisonPlanner {
    static func makePlan(
        candidates: [TestSentence],
        language: TestLanguage,
        trialsPerCondition: Int = 12,
        seed: UInt64
    ) -> SpeechComparisonPlan? {
        guard trialsPerCondition > 0 else { return nil }
        var generator = SeededSpeechGenerator(seed: seed)
        var seen = Set<String>()
        var unique = candidates.filter { sentence in
            let key = sentence.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
        unique.shuffle(using: &generator)
        guard unique.count >= trialsPerCondition * 2 else { return nil }

        var pool = Array(unique.prefix(max(trialsPerCondition * 2, min(unique.count, trialsPerCondition * 3))))
        var pairs: [(TestSentence, SpeechSentenceComplexity, TestSentence, SpeechSentenceComplexity)] = []
        while pairs.count < trialsPerCondition, !pool.isEmpty {
            let first = pool.removeFirst()
            let firstComplexity = SpeechSentenceComplexity.measure(first.text, language: language)
            guard !pool.isEmpty else { break }
            let partnerIndex = pool.indices.min { left, right in
                pairingDistance(firstComplexity, SpeechSentenceComplexity.measure(pool[left].text, language: language))
                    < pairingDistance(firstComplexity, SpeechSentenceComplexity.measure(pool[right].text, language: language))
            }!
            let second = pool.remove(at: partnerIndex)
            pairs.append((first, firstComplexity, second, SpeechSentenceComplexity.measure(second.text, language: language)))
        }
        guard pairs.count == trialsPerCondition else { return nil }

        var standard: [PlannedSpeechComparisonTrial] = []
        var equalized: [PlannedSpeechComparisonTrial] = []
        var balance = (words: 0, letters: 0, vowels: 0)

        for (index, pair) in pairs.enumerated() {
            let firstDelta = delta(pair.1, pair.3)
            let forward = balanceCost(
                words: balance.words + firstDelta.words,
                letters: balance.letters + firstDelta.letters,
                vowels: balance.vowels + firstDelta.vowels
            )
            let reverse = balanceCost(
                words: balance.words - firstDelta.words,
                letters: balance.letters - firstDelta.letters,
                vowels: balance.vowels - firstDelta.vowels
            )
            let useForward = forward == reverse ? Bool.random(using: &generator) : forward < reverse
            let standardSentence = useForward ? pair.0 : pair.2
            let standardComplexity = useForward ? pair.1 : pair.3
            let equalizedSentence = useForward ? pair.2 : pair.0
            let equalizedComplexity = useForward ? pair.3 : pair.1
            let chosenDelta = delta(standardComplexity, equalizedComplexity)
            balance.words += chosenDelta.words
            balance.letters += chosenDelta.letters
            balance.vowels += chosenDelta.vowels

            standard.append(PlannedSpeechComparisonTrial(
                pairIndex: index,
                condition: .standard,
                sentence: standardSentence.text,
                complexity: standardComplexity
            ))
            equalized.append(PlannedSpeechComparisonTrial(
                pairIndex: index,
                condition: .audiogramEQ,
                sentence: equalizedSentence.text,
                complexity: equalizedComplexity
            ))
        }

        standard.shuffle(using: &generator)
        equalized.shuffle(using: &generator)
        let blockOrder: [SpeechComparisonCondition] = Bool.random(using: &generator)
            ? [.standard, .audiogramEQ]
            : [.audiogramEQ, .standard]
        let trials = blockOrder.flatMap { $0 == .standard ? standard : equalized }
        return SpeechComparisonPlan(seed: seed, blockOrder: blockOrder, trials: trials)
    }

    private static func pairingDistance(
        _ first: SpeechSentenceComplexity,
        _ second: SpeechSentenceComplexity
    ) -> Double {
        let sharedContentPenalty = Double(first.contentWords.intersection(second.contentWords).count) * 30
        return Double(abs(first.wordCount - second.wordCount)) * 12
            + Double(abs(first.letterCount - second.letterCount)) * 0.35
            + Double(abs(first.vowelGroupCount - second.vowelGroupCount)) * 1.5
            + sharedContentPenalty
    }

    private static func delta(
        _ first: SpeechSentenceComplexity,
        _ second: SpeechSentenceComplexity
    ) -> (words: Int, letters: Int, vowels: Int) {
        (first.wordCount - second.wordCount, first.letterCount - second.letterCount, first.vowelGroupCount - second.vowelGroupCount)
    }

    private static func balanceCost(words: Int, letters: Int, vowels: Int) -> Double {
        Double(abs(words)) * 12 + Double(abs(letters)) * 0.35 + Double(abs(vowels)) * 1.5
    }
}

struct SpeechComparisonBand: Codable, Hashable {
    let frequency: Double
    let leftGainDB: Double
    let rightGainDB: Double
}

struct SpeechComparisonTrial: Identifiable, Codable, Hashable {
    let id: UUID
    let pairIndex: Int
    let condition: SpeechComparisonCondition
    let sentence: String
    let response: String
    let score: Double
    let responseTime: TimeInterval
    let playbackCount: Int
    let complexity: SpeechSentenceComplexity
    let timestamp: Date

    init(
        id: UUID = UUID(),
        pairIndex: Int,
        condition: SpeechComparisonCondition,
        sentence: String,
        response: String,
        score: Double,
        responseTime: TimeInterval,
        playbackCount: Int,
        complexity: SpeechSentenceComplexity,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.pairIndex = pairIndex
        self.condition = condition
        self.sentence = sentence
        self.response = response
        self.score = score
        self.responseTime = responseTime
        self.playbackCount = playbackCount
        self.complexity = complexity
        self.timestamp = timestamp
    }
}

struct SpeechEQComparisonTest: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    let date: Date
    let language: TestLanguage
    let voiceProfile: VoiceProfile
    let resolvedVoiceName: String?
    let noise: NoiseKind
    let snrDB: Double
    let pureToneTestID: UUID
    let pureToneTestName: String
    let pureToneRouteName: String
    let maximumBoostDB: Double
    let bands: [SpeechComparisonBand]
    let blockOrder: [SpeechComparisonCondition]
    let planSeed: UInt64
    let trials: [SpeechComparisonTrial]

    var standardTrials: [SpeechComparisonTrial] { trials.filter { $0.condition == .standard } }
    var equalizedTrials: [SpeechComparisonTrial] { trials.filter { $0.condition == .audiogramEQ } }
    var standardMeanScore: Double { mean(standardTrials.map(\.score)) }
    var equalizedMeanScore: Double { mean(equalizedTrials.map(\.score)) }
    var differencePercentagePoints: Double { (equalizedMeanScore - standardMeanScore) * 100 }
    var pairedDifferences: [Double] {
        let standard = Dictionary(uniqueKeysWithValues: standardTrials.map { ($0.pairIndex, $0.score) })
        return equalizedTrials.compactMap { trial in standard[trial.pairIndex].map { trial.score - $0 } }
    }
    var pairedConfidenceInterval95: ClosedRange<Double>? {
        let values = pairedDifferences
        guard values.count >= 4 else { return nil }
        let average = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count - 1)
        let margin = 1.96 * sqrt(variance / Double(values.count))
        return ((average - margin) * 100)...((average + margin) * 100)
    }
    var maximumSharedContentWordsPerPair: Int {
        var maximum = 0
        for equalized in equalizedTrials {
            guard let standard = standardTrials.first(where: { $0.pairIndex == equalized.pairIndex }) else { continue }
            maximum = max(maximum, standard.complexity.contentWords.intersection(equalized.complexity.contentWords).count)
        }
        return maximum
    }
    var wordCountDifference: Double { complexityMean(standardTrials, \.wordCount) - complexityMean(equalizedTrials, \.wordCount) }
    var letterCountDifference: Double { complexityMean(standardTrials, \.letterCount) - complexityMean(equalizedTrials, \.letterCount) }
    var vowelGroupDifference: Double { complexityMean(standardTrials, \.vowelGroupCount) - complexityMean(equalizedTrials, \.vowelGroupCount) }

    private func complexityMean(_ trials: [SpeechComparisonTrial], _ keyPath: KeyPath<SpeechSentenceComplexity, Int>) -> Double {
        mean(trials.map { Double($0.complexity[keyPath: keyPath]) })
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

private struct SeededSpeechGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
