import SwiftUI
import Charts

struct PredictiveListeningView: View {
    private enum RunState: Equatable {
        case setup
        case running
        case complete
    }

    @EnvironmentObject private var model: AppModel
    @StateObject private var audio = StimulusEngine()
    @State private var runState: RunState = .setup
    @State private var testName = ""
    @State private var noise: NoiseKind = .restaurant
    @State private var plan: [PredictiveTrialPlan] = []
    @State private var trialIndex = 0
    @State private var response = ""
    @State private var confidence = 3.0
    @State private var effort = 3.0
    @State private var presentationCount = 0
    @State private var stimulusStartedAt: Date?
    @State private var trials: [PredictiveListeningTrial] = []
    @State private var savedTest: PredictiveListeningTest?
    @State private var runLanguage: TestLanguage?
    @State private var runVoice: VoiceProfile?
    @State private var anchorSNR80 = 4.0

    private var language: TestLanguage { runLanguage ?? model.selectedLanguage }
    private var voice: VoiceProfile { runVoice ?? model.selectedVoice }
    private var current: PredictiveTrialPlan? {
        guard plan.indices.contains(trialIndex) else { return nil }
        return plan[trialIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock(
                    language.text("Predictive Listening", "Escucha predictiva"),
                    subtitle: language.text(
                        "Measure context, auditory closure, prediction errors, adaptation, and listening effort.",
                        "Mide contexto, cierre auditivo, errores de predicción, adaptación y esfuerzo auditivo."
                    )
                )

                switch runState {
                case .setup:
                    setupContent
                case .running:
                    runningContent
                case .complete:
                    completionContent
                }
            }
            .padding()
        }
        .background(Color.black)
        .navigationTitle(language.text("Predictive Listening", "Escucha predictiva"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if testName.isEmpty {
                testName = model.defaultTestName(for: .predictiveListening, language: model.selectedLanguage)
            }
        }
        .onChange(of: model.selectedLanguage) { _, newLanguage in
            if runState == .setup {
                testName = model.defaultTestName(for: .predictiveListening, language: newLanguage)
            }
        }
        .onDisappear { audio.stop() }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TestSetupCard(
                testName: $testName,
                language: $model.selectedLanguage,
                voice: $model.selectedVoice,
                includesVoice: true,
                locked: false
            )

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(language.text("Individual difficulty", "Dificultad individual"), systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Spacer()
                        Text(signedValue(proposedAnchorSNR) + " dB SNR")
                            .font(.subheadline.bold()).foregroundStyle(.indigo)
                    }
                    Text(language.text(
                        model.profile.speechTestPoints.isEmpty
                            ? "No saved speech curve is available, so the test will begin at a conservative default. Complete Speech in Noise first for better matching."
                            : "Context and prediction trials will use your latest SNR80 so the task is challenging without being dominated by audibility.",
                        model.profile.speechTestPoints.isEmpty
                            ? "No hay una curva de habla guardada; la prueba comenzará con un valor predeterminado conservador. Completa primero Habla con ruido para ajustar mejor la dificultad."
                            : "Los ensayos de contexto y predicción usarán tu SNR80 más reciente para mantener el reto sin que la audibilidad domine el resultado."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)

                    Picker(language.text("Background", "Fondo sonoro"), selection: $noise) {
                        ForEach(NoiseKind.allCases) { kind in
                            Text(kind.displayName(in: language)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(language.text("Four complementary stages", "Cuatro etapas complementarias"))
                        .font(.headline)
                    ForEach(Array(PredictiveModule.allCases.enumerated()), id: \.element.id) { index, module in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(stageColor(module).opacity(0.16)).frame(width: 38, height: 38)
                                Image(systemName: module.symbol).foregroundStyle(stageColor(module))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(module.displayName(in: language))").font(.subheadline.bold())
                                Text(moduleDescription(module)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text("Behavioral research measure", "Medida conductual de investigación"), systemImage: "brain.head.profile")
                        .font(.headline).foregroundStyle(.orange)
                    Text(language.text(
                        "The app infers listening behavior from answers, timing, confidence, and effort. It does not record neural activity and cannot diagnose cognition or central auditory disorders.",
                        "La app infiere el comportamiento auditivo mediante respuestas, tiempo, confianza y esfuerzo. No registra actividad neuronal ni diagnostica la cognición o trastornos auditivos centrales."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Button(action: startTest) {
                Label(language.text("Begin 36-trial profile", "Comenzar perfil de 36 ensayos"), systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
    }

    @ViewBuilder
    private var runningContent: some View {
        if let current {
            GlassCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(current.module.displayName(in: language), systemImage: current.module.symbol)
                            .font(.headline).foregroundStyle(stageColor(current.module))
                        Spacer()
                        Text("\(trialIndex + 1) / \(plan.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(trialIndex), total: Double(plan.count))
                        .tint(stageColor(current.module))
                    stageTimeline(currentModule: current.module)
                    HStack {
                        Text(stageInstruction(current)).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Label(estimatedRemaining, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 15) {
                    Text(language.text(
                        "The sentence stays hidden. Listen once if possible.",
                        "La frase permanece oculta. Escúchala una sola vez si es posible."
                    ))
                    .font(.subheadline).foregroundStyle(.secondary)

                    Button(action: playCurrent) {
                        VStack(spacing: 8) {
                            Image(systemName: audio.isPlaying ? "waveform" : "ear.fill").font(.largeTitle)
                            Text(playButtonTitle).font(.title3.bold())
                            if presentationCount > 0 {
                                Text(language.text("Replays reduce the reliability score", "Las repeticiones reducen la fiabilidad"))
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stageColor(current.module))
                    .disabled(audio.isPlaying)

                    TextField(responsePlaceholder(current), text: $response, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(current.responseMode == .fullSentence ? 3...5 : 1...2)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    responseScales
                    AudioErrorText(message: audio.lastError)

                    Button(action: submitCurrent) {
                        Label(language.text("Record response", "Guardar respuesta"), systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        presentationCount == 0 || audio.isPlaying ||
                        response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }

            GlassCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
                    Text(language.text(
                        "Correct answers are not revealed during the run, preventing feedback from changing later prediction and adaptation trials.",
                        "Las respuestas correctas no se muestran durante la prueba para evitar que la retroalimentación cambie los ensayos posteriores."
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var responseScales: some View {
        VStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(language.text("Confidence", "Confianza")).font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(confidence)) / 5").monospacedDigit().foregroundStyle(.cyan)
                }
                Slider(value: $confidence, in: 1...5, step: 1).tint(.cyan)
                HStack {
                    Text(language.text("Guessing", "Adivinando"))
                    Spacer()
                    Text(language.text("Certain", "Seguro"))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(language.text("Listening effort", "Esfuerzo auditivo")).font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(effort)) / 5").monospacedDigit().foregroundStyle(.orange)
                }
                Slider(value: $effort, in: 1...5, step: 1).tint(.orange)
                HStack {
                    Text(language.text("Easy", "Fácil"))
                    Spacer()
                    Text(language.text("Very effortful", "Mucho esfuerzo"))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let savedTest {
                GlassCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(language.text("Predictive profile saved", "Perfil predictivo guardado"), systemImage: "checkmark.seal.fill")
                            .font(.title3.bold()).foregroundStyle(.green)
                        Text(savedTest.name).font(.headline)
                        Text(language.text(
                            "These dimensions describe behavior under this test protocol; they are not a cognitive or neurological diagnosis.",
                            "Estas dimensiones describen el comportamiento bajo este protocolo; no son un diagnóstico cognitivo ni neurológico."
                        ))
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                PredictiveListeningSummary(test: savedTest, language: language)
            }

            Button(action: reset) {
                Label(language.text("Run another predictive profile", "Hacer otro perfil predictivo"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
    }

    private var proposedAnchorSNR: Double {
        model.profile.speechTestPoints.isEmpty ? 4 : min(14, max(-6, model.profile.snr80))
    }

    private var playButtonTitle: String {
        if audio.isPlaying { return language.text("Playing…", "Reproduciendo…") }
        return presentationCount == 0
            ? language.text("Play hidden sentence", "Reproducir frase oculta")
            : language.text("Replay sentence", "Repetir frase")
    }

    private var estimatedRemaining: String {
        let seconds = max(0, plan.count - trialIndex) * 24
        return language.text("~\(max(1, Int(ceil(Double(seconds) / 60)))) min", "~\(max(1, Int(ceil(Double(seconds) / 60)))) min")
    }

    private func startTest() {
        audio.stop()
        runLanguage = model.selectedLanguage
        runVoice = model.selectedVoice
        anchorSNR80 = proposedAnchorSNR
        plan = PredictiveCorpus.makePlan(for: model.selectedLanguage)
        trialIndex = 0
        trials = []
        savedTest = nil
        resetResponseControls()
        runState = .running
    }

    private func playCurrent() {
        guard let current else { return }
        presentationCount += 1
        stimulusStartedAt = Date()
        Task {
            switch current.condition {
            case .highContext, .lowContext, .misleadingContext:
                await audio.playSpeechInNoise(
                    current.stimulusText,
                    snrDB: anchorSNR80,
                    noise: noise,
                    language: language,
                    voiceProfile: voice
                )
            case .silentGap, .noiseFilledGap:
                await audio.playInterruptedSpeech(
                    current.stimulusText,
                    condition: current.condition,
                    language: language,
                    voiceProfile: voice
                )
            case .filteredSpeech:
                await audio.playFilteredSpeech(
                    current.stimulusText,
                    language: language,
                    voiceProfile: voice
                )
            }
        }
    }

    private func submitCurrent() {
        guard let current else { return }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let score = WordScorer.score(reference: current.referenceText, response: trimmed)
        let intrusion = current.expectedIntrusionWord.map {
            WordScorer.score(reference: $0, response: trimmed) >= 0.999
        } ?? false
        let usesSNR = current.condition == .highContext || current.condition == .lowContext || current.condition == .misleadingContext

        trials.append(PredictiveListeningTrial(
            module: current.module,
            condition: current.condition,
            promptID: current.promptID,
            stimulusText: current.stimulusText,
            referenceText: current.referenceText,
            expectedIntrusionWord: current.expectedIntrusionWord,
            response: trimmed,
            score: score,
            expectedIntrusion: intrusion,
            snrDB: usesSNR ? anchorSNR80 : nil,
            noiseKind: usesSNR ? noise : nil,
            responseTime: Date().timeIntervalSince(stimulusStartedAt ?? Date()),
            presentationCount: presentationCount,
            confidence: Int(confidence),
            effort: Int(effort)
        ))

        audio.stop()
        trialIndex += 1
        if trialIndex >= plan.count {
            finishTest()
        } else {
            resetResponseControls()
        }
    }

    private func finishTest() {
        let test = PredictiveListeningTest(
            name: testName,
            language: language,
            voiceProfile: voice,
            resolvedVoiceName: audio.lastResolvedVoiceName,
            anchorSNR80: anchorSNR80,
            noiseKind: noise,
            trials: trials
        )
        savedTest = model.savePredictiveListeningTest(test)
        runState = .complete
    }

    private func reset() {
        audio.stop()
        runState = .setup
        runLanguage = nil
        runVoice = nil
        testName = model.defaultTestName(for: .predictiveListening, language: model.selectedLanguage)
        plan = []
        trialIndex = 0
        trials = []
        savedTest = nil
        resetResponseControls()
    }

    private func resetResponseControls() {
        response = ""
        confidence = 3
        effort = 3
        presentationCount = 0
        stimulusStartedAt = nil
    }

    private func responsePlaceholder(_ trial: PredictiveTrialPlan) -> String {
        trial.responseMode == .finalWord
            ? language.text("Type only the final word", "Escribe solo la última palabra")
            : language.text("Type as much of the sentence as you heard", "Escribe todo lo que hayas entendido")
    }

    private func stageInstruction(_ trial: PredictiveTrialPlan) -> String {
        switch trial.module {
        case .semanticContext:
            return language.text("Identify the final word.", "Identifica la última palabra.")
        case .auditoryClosure:
            return language.text("Reconstruct as much of the interrupted sentence as possible.", "Reconstruye todo lo posible de la frase interrumpida.")
        case .predictionCost:
            return language.text("Report the word that was actually spoken, not the expected word.", "Indica la palabra realmente pronunciada, no la esperada.")
        case .adaptation:
            return language.text("Follow the filtered speech; the processing remains consistent.", "Sigue el habla filtrada; el procesamiento se mantiene constante.")
        }
    }

    private func moduleDescription(_ module: PredictiveModule) -> String {
        switch module {
        case .semanticContext:
            return language.text("Compares helpful and neutral sentence context at your SNR80.", "Compara contexto útil y neutro usando tu SNR80.")
        case .auditoryClosure:
            return language.text("Compares silent gaps with identical gaps filled by noise.", "Compara silencios con huecos idénticos llenos de ruido.")
        case .predictionCost:
            return language.text("Counts expectation-driven responses when context is misleading.", "Cuenta respuestas guiadas por expectativas cuando el contexto engaña.")
        case .adaptation:
            return language.text("Estimates improvement across a consistent filtered-speech block.", "Estima la mejora durante un bloque constante de habla filtrada.")
        }
    }

    private func stageTimeline(currentModule: PredictiveModule) -> some View {
        HStack(spacing: 6) {
            ForEach(PredictiveModule.allCases) { module in
                let completed = moduleOrder(module) < moduleOrder(currentModule)
                let active = module == currentModule
                HStack(spacing: 5) {
                    Image(systemName: completed ? "checkmark.circle.fill" : module.symbol)
                    if active { Text("\(moduleOrder(module) + 1)").font(.caption.bold()) }
                }
                .foregroundStyle(completed || active ? stageColor(module) : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? stageColor(module).opacity(0.15) : Color.white.opacity(0.035))
                )
            }
        }
        .accessibilityLabel(currentModule.displayName(in: language))
    }

    private func moduleOrder(_ module: PredictiveModule) -> Int {
        PredictiveModule.allCases.firstIndex(of: module) ?? 0
    }

    private func stageColor(_ module: PredictiveModule) -> Color {
        switch module {
        case .semanticContext: return .cyan
        case .auditoryClosure: return .purple
        case .predictionCost: return .orange
        case .adaptation: return .green
        }
    }

    private func signedValue(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}

struct PredictiveListeningSummary: View {
    let test: PredictiveListeningTest
    let language: TestLanguage

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 10) {
                PredictiveMetricCard(
                    title: language.text("Context benefit", "Beneficio del contexto"),
                    value: signedPercent(test.contextBenefit),
                    subtitle: language.text("High minus neutral", "Alto menos neutro"),
                    color: .cyan
                )
                PredictiveMetricCard(
                    title: language.text("Restoration benefit", "Beneficio de restauración"),
                    value: signedPercent(test.restorationBenefit),
                    subtitle: language.text("Noise gaps minus silence", "Ruido menos silencio"),
                    color: .purple
                )
                PredictiveMetricCard(
                    title: language.text("Prediction cost", "Costo de predicción"),
                    value: plainPercent(test.predictionCost),
                    subtitle: language.text("Expected-word intrusions", "Intrusiones esperadas"),
                    color: .orange
                )
                PredictiveMetricCard(
                    title: language.text("Adaptation gain", "Ganancia de adaptación"),
                    value: signedPercent(test.adaptationGain),
                    subtitle: language.text("Late minus early", "Final menos inicial"),
                    color: .green
                )
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text("Behavioral profile", "Perfil conductual")).font(.headline)
                    Chart(metricValues) { metric in
                        BarMark(
                            x: .value("Percent", metric.value),
                            y: .value("Metric", metric.title)
                        )
                        .foregroundStyle(metric.color.gradient)
                        RuleMark(x: .value("Zero", 0)).foregroundStyle(.secondary)
                    }
                    .chartXScale(domain: -100...100)
                    .frame(height: 210)
                    Text(language.text(
                        "Positive values indicate benefit or improvement, except Prediction cost, where lower is better.",
                        "Los valores positivos indican beneficio o mejora, excepto Costo de predicción, donde un valor menor es mejor."
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text(language.text("Effort and quality", "Esfuerzo y calidad")).font(.headline)
                    LabeledContent(language.text("Average confidence", "Confianza media"), value: String(format: "%.1f / 5", test.averageConfidence))
                    LabeledContent(language.text("Average effort", "Esfuerzo medio"), value: String(format: "%.1f / 5", test.averageEffort))
                    LabeledContent(language.text("Average response time", "Tiempo medio de respuesta"), value: String(format: "%.1f s", test.averageResponseTime))
                    LabeledContent(language.text("Protocol reliability", "Fiabilidad del protocolo"), value: String(format: "%.0f%%", test.reliabilityScore))
                    LabeledContent(language.text("Trials", "Ensayos"), value: "\(test.trials.count)")
                    LabeledContent(language.text("Speech anchor", "Referencia de habla"), value: String(format: "%+.1f dB SNR", test.anchorSNR80))
                }
                .font(.subheadline)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text("Condition detail", "Detalle de condiciones")).font(.headline)
                    LabeledContent(language.text("High-context accuracy", "Precisión con contexto alto"), value: plainPercent(test.contextHighAccuracy))
                    LabeledContent(language.text("Neutral-context accuracy", "Precisión con contexto neutro"), value: plainPercent(test.contextLowAccuracy))
                    LabeledContent(language.text("Silent-gap accuracy", "Precisión con huecos silenciosos"), value: plainPercent(test.silentGapAccuracy))
                    LabeledContent(language.text("Noise-filled-gap accuracy", "Precisión con huecos de ruido"), value: plainPercent(test.noiseFilledAccuracy))
                }
                .font(.subheadline)
            }
        }
    }

    private var metricValues: [PredictiveMetricValue] {
        [
            .init(title: language.text("Context", "Contexto"), value: test.contextBenefit, color: .cyan),
            .init(title: language.text("Restoration", "Restauración"), value: test.restorationBenefit, color: .purple),
            .init(title: language.text("Prediction cost", "Costo"), value: test.predictionCost, color: .orange),
            .init(title: language.text("Adaptation", "Adaptación"), value: test.adaptationGain, color: .green)
        ]
    }

    private func signedPercent(_ value: Double) -> String { String(format: "%+.0f%%", value) }
    private func plainPercent(_ value: Double) -> String { String(format: "%.0f%%", value) }
}

private struct PredictiveMetricValue: Identifiable {
    let id = UUID()
    let title: String
    let value: Double
    let color: Color
}

private struct PredictiveMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22)))
    }
}
