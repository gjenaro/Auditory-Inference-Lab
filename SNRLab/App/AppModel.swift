import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: HearingProfile {
        didSet { saveProfile() }
    }

    @Published private(set) var history: [TestRecord] {
        didSet { saveHistory() }
    }

    @Published private(set) var personalizationExperiments: [PersonalizationExperiment] {
        didSet { savePersonalizationExperiments() }
    }

    @Published var selectedLanguage: TestLanguage {
        didSet { UserDefaults.standard.set(selectedLanguage.rawValue, forKey: languageKey) }
    }

    @Published var selectedVoice: VoiceProfile {
        didSet { UserDefaults.standard.set(selectedVoice.rawValue, forKey: voiceKey) }
    }

    private let profileKey = "auditoryinference.profile.v1"
    private let historyKey = "auditoryinference.history.v1"
    private let experimentKey = "auditoryinference.experiments.v1"
    private let languageKey = "auditoryinference.language.v1"
    private let voiceKey = "auditoryinference.voice.v1"
    private let sentencePositionKeyPrefix = "auditoryinference.sentence-position.v1."

    init() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(HearingProfile.self, from: data) {
            profile = decoded
        } else {
            profile = HearingProfile()
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([TestRecord].self, from: data) {
            history = decoded
        } else {
            history = []
        }

        if let data = UserDefaults.standard.data(forKey: experimentKey),
           let decoded = try? JSONDecoder().decode([PersonalizationExperiment].self, from: data) {
            personalizationExperiments = decoded
        } else {
            personalizationExperiments = []
        }

        selectedLanguage = TestLanguage(
            rawValue: UserDefaults.standard.string(forKey: languageKey) ?? ""
        ) ?? .english
        selectedVoice = VoiceProfile(
            rawValue: UserDefaults.standard.string(forKey: voiceKey) ?? ""
        ) ?? .woman

    }

    func defaultTestName(for kind: TestKind, language: TestLanguage? = nil) -> String {
        let language = language ?? selectedLanguage
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(kind.displayName(in: language)) — \(formatter.string(from: Date()))"
    }

    /// Returns speech material without replacement across test runs. The fixed
    /// permutation avoids clusters from the matrix corpus while preserving a
    /// reproducible 144-sentence cycle for each language.
    func allocateSentences(language: TestLanguage, count: Int) -> [TestSentence] {
        let bank = TestSentence.bank(for: language)
        guard !bank.isEmpty, count > 0 else { return [] }
        let key = sentencePositionKeyPrefix + language.rawValue
        let start = max(0, UserDefaults.standard.integer(forKey: key))
        let result = (0..<count).map { offset -> TestSentence in
            let absolute = start + offset
            let cycle = absolute / bank.count
            let slot = absolute % bank.count
            let index = (slot * 37 + cycle * 53) % bank.count
            return bank[index]
        }
        UserDefaults.standard.set(start + count, forKey: key)
        return result
    }

    func saveSpeechTest(
        name: String,
        points: [RecognitionPoint],
        language: TestLanguage,
        voice: VoiceProfile,
        resolvedVoiceName: String?
    ) {
        let fit = PsychometricEstimator.fit(points)
        profile.speechTestPoints = points
        profile.snr50 = fit.snr50
        profile.logisticSlope = fit.slope
        profile.snr80 = fit.snr80
        profile.snr90 = fit.snr90
        profile.lastUpdated = Date()

        add(TestRecord(
            name: cleanName(name, kind: .speechInNoise, language: language),
            kind: .speechInNoise,
            language: language,
            voiceProfile: voice,
            resolvedVoiceName: resolvedVoiceName,
            snr50: fit.snr50,
            snr80: fit.snr80,
            snr90: fit.snr90,
            speechPoints: points
        ))
    }

    func saveVolumeTest(
        name: String,
        points: [VolumePoint],
        language: TestLanguage,
        voice: VoiceProfile,
        resolvedVoiceName: String?
    ) {
        profile.volumePoints = points
        profile.lastUpdated = Date()
        add(TestRecord(
            name: cleanName(name, kind: .volume, language: language),
            kind: .volume,
            language: language,
            voiceProfile: voice,
            resolvedVoiceName: resolvedVoiceName,
            volumePoints: points
        ))
    }

    func saveFrequencyTest(name: String, thresholds: [FrequencyThreshold], language: TestLanguage) {
        profile.frequencyThresholds = thresholds
        profile.lastUpdated = Date()
        add(TestRecord(
            name: cleanName(name, kind: .frequency, language: language),
            kind: .frequency,
            language: language,
            frequencyThresholds: thresholds
        ))
    }

    @discardableResult
    func savePureToneTest(_ test: BilateralPureToneTest, language: TestLanguage) -> BilateralPureToneTest {
        var saved = test
        saved.name = cleanName(test.name, kind: .frequency, language: language)
        profile.latestPureToneTest = saved
        profile.lastUpdated = saved.date
        add(TestRecord(
            id: saved.id,
            name: saved.name,
            date: saved.date,
            kind: .frequency,
            language: language,
            pureToneTest: saved
        ))
        return saved
    }

    func saveNoiseTest(
        name: String,
        points: [RecognitionPoint],
        noise: NoiseKind,
        threshold: Double,
        language: TestLanguage,
        voice: VoiceProfile,
        resolvedVoiceName: String?
    ) {
        profile.noiseThresholds[noise.rawValue] = threshold
        profile.lastUpdated = Date()
        add(TestRecord(
            name: cleanName(name, kind: .noiseProfile, language: language),
            kind: .noiseProfile,
            language: language,
            voiceProfile: voice,
            resolvedVoiceName: resolvedVoiceName,
            snr90: threshold,
            speechPoints: points,
            noiseKind: noise,
            noiseThreshold: threshold
        ))
    }

    @discardableResult
    func savePredictiveListeningTest(_ test: PredictiveListeningTest) -> PredictiveListeningTest {
        var saved = test
        saved.name = cleanName(test.name, kind: .predictiveListening, language: test.language)
        profile.latestPredictiveTest = saved
        profile.lastUpdated = saved.date
        add(TestRecord(
            id: saved.id,
            name: saved.name,
            date: saved.date,
            kind: .predictiveListening,
            language: saved.language,
            voiceProfile: saved.voiceProfile,
            resolvedVoiceName: saved.resolvedVoiceName,
            predictiveTest: saved
        ))
        return saved
    }

    func reset() {
        profile = HearingProfile()
        history = []
        personalizationExperiments = []
    }

    func upsertPersonalizationExperiment(_ experiment: PersonalizationExperiment) {
        var updated = personalizationExperiments.filter { $0.id != experiment.id }
        updated.insert(experiment, at: 0)
        personalizationExperiments = Array(updated.prefix(50))
    }

    private func cleanName(_ name: String, kind: TestKind, language: TestLanguage) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTestName(for: kind, language: language) : trimmed
    }

    private func add(_ record: TestRecord) {
        history = Array(([record] + history).prefix(100))
    }

    private func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func savePersonalizationExperiments() {
        if let data = try? JSONEncoder().encode(personalizationExperiments) {
            UserDefaults.standard.set(data, forKey: experimentKey)
        }
    }

}
