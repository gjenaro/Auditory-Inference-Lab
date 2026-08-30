import SwiftUI
import Charts

struct SpeechEQComparisonView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var audio = StimulusEngine()
    @AppStorage("auditoryinference.speechComparison.pureToneSource.v1") private var selectedPureToneSource = "latest"
    @AppStorage("auditoryinference.speechComparison.maximumBoost.v1") private var maximumBoostDB = 6.0

    @State private var testName = ""
    @State private var noise: NoiseKind = .restaurant
    @State private var snrDB = 3.0
    @State private var phase: ComparisonPhase = .setup
    @State private var plan: SpeechComparisonPlan?
    @State private var currentIndex = 0
    @State private var response = ""
    @State private var playbackCount = 0
    @State private var responseClock = Date()
    @State private var recordedTrials: [SpeechComparisonTrial] = []
    @State private var activeBands: [StereoCompensationBand] = []
    @State private var savedTest: SpeechEQComparisonTest?
    @State private var routeStatus: AudioOutputRouteStatus?
    @State private var setupError: String?

    private let trialsPerCondition = 12
    private var language: TestLanguage { model.selectedLanguage }
    private var totalTrials: Int { trialsPerCondition * 2 }
    private var pureToneRecords: [TestRecord] {
        model.history.filter { $0.kind == .frequency && $0.pureToneTest != nil }
    }
    private var selectedPureToneTest: BilateralPureToneTest? {
        if selectedPureToneSource == "latest" { return model.profile.latestPureToneTest }
        return pureToneRecords.first(where: { $0.id.uuidString == selectedPureToneSource })?.pureToneTest
    }
    private var currentTrial: PlannedSpeechComparisonTrial? {
        guard let plan, plan.trials.indices.contains(currentIndex) else { return nil }
        return plan.trials[currentIndex]
    }
    private var currentBlock: Int { min(2, currentIndex / trialsPerCondition + 1) }
    private var appliedBands: [StereoCompensationBand] {
        CompensationDesigner.bands(from: selectedPureToneTest, maximumBoostDB: maximumBoostDB)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock(
                    TestKind.speechEQComparison.displayName(in: language),
                    subtitle: language.text(
                        "Compare standard speech with the same signal processed by your left/right audiogram EQ.",
                        "Compara el habla estándar con la misma señal procesada por tu EQ de audiograma izquierdo/derecho."
                    )
                )

                switch phase {
                case .setup: setupContent
                case .testing: testingContent
                case .betweenBlocks: breakContent
                case .complete: completionContent
                }
            }
            .padding()
        }
        .background(Color.black)
        .navigationTitle(language.text("Standard vs EQ", "Estándar vs EQ"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeMeasurementSelection()
            if testName.isEmpty { testName = model.defaultTestName(for: .speechEQComparison, language: language) }
            if phase == .setup { snrDB = min(12, max(-5, model.profile.snr80)) }
            refreshRoute()
        }
        .onChange(of: model.selectedLanguage) { _, _ in
            guard phase == .setup else { return }
            testName = model.defaultTestName(for: .speechEQComparison, language: language)
        }
        .onChange(of: model.history) { _, _ in normalizeMeasurementSelection() }
        .onDisappear { audio.stop() }
    }

    private var setupContent: some View {
        Group {
            TestSetupCard(
                testName: $testName,
                language: $model.selectedLanguage,
                voice: $model.selectedVoice,
                includesVoice: true,
                locked: false
            )

            GlassCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label(language.text("Controlled comparison", "Comparación controlada"), systemImage: "checkmark.shield.fill")
                        .font(.headline).foregroundStyle(.cyan)
                    Text(language.text(
                        "Two 12-sentence blocks use different material matched for word count, letter count, and vowel-group complexity. Block order is randomized and hidden until the result.",
                        "Dos bloques de 12 frases usan material diferente y equilibrado por palabras, letras y grupos vocálicos. El orden se aleatoriza y se oculta hasta el resultado."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        setupMetric(language.text("Sentences", "Frases"), "24")
                        setupMetric(language.text("Conditions", "Condiciones"), "2")
                        setupMetric(language.text("Est. time", "Tiempo est."), "7–10 min")
                    }
                }
            }

            measurementCard
            playbackCard
            SpeechComparisonFilterCard(bands: appliedBands, maximumBoostDB: maximumBoostDB, language: language)

            if let setupError {
                Label(setupError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }

            Button(action: startTest) {
                Label(language.text("Begin comparison", "Iniciar comparación"), systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPureToneTest == nil)

            GlassCard {
                Text(language.text(
                    "Exploratory, uncalibrated research feature. It does not establish treatment benefit and is not a hearing-aid fitting or clinical speech test.",
                    "Función exploratoria sin calibrar. No demuestra beneficio terapéutico ni es una adaptación de audífono o prueba clínica del habla."
                ))
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var measurementCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(language.text("Audiogram used", "Audiograma utilizado"), systemImage: "waveform.path.ecg")
                    .font(.headline)
                Picker(language.text("Bilateral measurement", "Medición bilateral"), selection: $selectedPureToneSource) {
                    Text(language.text("Latest bilateral result", "Último resultado bilateral")).tag("latest")
                    ForEach(pureToneRecords) { record in
                        Text(recordOptionLabel(record)).tag(record.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .tint(.green)

                if let selectedPureToneTest {
                    LabeledContent(language.text("Headset used for measurement", "Auriculares de la medición"), value: selectedPureToneTest.outputRouteName)
                        .font(.footnote)
                    Text(language.text(
                        "Use the same headset, fit, iPhone volume, and operating mode used for this audiogram.",
                        "Usa los mismos auriculares, ajuste, volumen del iPhone y modo operativo del audiograma."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(language.text(
                        "A saved bilateral pure-tone result is required.",
                        "Se necesita un resultado bilateral guardado de tonos puros."
                    ))
                    .font(.footnote).foregroundStyle(.orange)
                    NavigationLink(destination: FrequencySensitivityView()) {
                        Label(language.text("Run pure-tone test", "Hacer prueba de tonos"), systemImage: "ear")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                HStack {
                    Label(routeStatus?.name ?? language.text("Checking output…", "Comprobando salida…"), systemImage: "airpodspro")
                        .font(.footnote)
                    Spacer()
                    Button(language.text("Refresh", "Actualizar"), action: refreshRoute).font(.caption)
                }
                if let routeStatus {
                    Label(
                        routeStatus.isReadyForBilateralTest
                            ? language.text("Supported stereo headset ready", "Auriculares estéreo compatibles listos")
                            : language.text("Connect stereo AirPods or Bose QuietComfort", "Conecta AirPods o Bose QuietComfort estéreo"),
                        systemImage: routeStatus.isReadyForBilateralTest ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption).foregroundStyle(routeStatus.isReadyForBilateralTest ? .green : .orange)
                }
            }
        }
    }

    private var playbackCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(language.text("Fixed playback settings", "Ajustes fijos de reproducción"), systemImage: "dial.medium.fill")
                    .font(.headline)
                Picker(language.text("Background", "Fondo"), selection: $noise) {
                    ForEach(NoiseKind.allCases) { kind in
                        Text(kind.displayName(in: language)).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("SNR")
                    Slider(value: $snrDB, in: -5...12, step: 1)
                    Text("\(signed(snrDB)) dB").monospacedDigit().frame(width: 62, alignment: .trailing)
                }
                HStack {
                    Text(language.text("Maximum EQ boost", "Refuerzo EQ máximo"))
                    Slider(value: $maximumBoostDB, in: 0...20, step: 1)
                    Text("\(Int(maximumBoostDB)) dB").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Text(language.text(
                    "Voice, masker, nominal SNR, and master headroom remain identical in both blocks. The combined speech + noise signal is filtered only in the EQ condition.",
                    "La voz, el ruido, el SNR nominal y el margen maestro son idénticos en ambos bloques. La señal combinada de habla + ruido solo se filtra en la condición EQ."
                ))
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var testingContent: some View {
        Group {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("Block \(currentBlock) of 2", "Bloque \(currentBlock) de 2")).font(.headline)
                            Text(language.text(
                                "Sentence \(currentIndex % trialsPerCondition + 1) of \(trialsPerCondition)",
                                "Frase \(currentIndex % trialsPerCondition + 1) de \(trialsPerCondition)"
                            ))
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(currentIndex + 1)/\(totalTrials)").font(.headline.monospacedDigit()).foregroundStyle(.cyan)
                    }
                    ProgressView(value: Double(currentIndex), total: Double(totalTrials)).tint(.cyan)

                    Text(language.text(
                        "The condition is intentionally hidden. Listen and type exactly what you heard.",
                        "La condición se oculta intencionalmente. Escucha y escribe exactamente lo que oíste."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)

                    Button(action: playCurrentSentence) {
                        Label(
                            audio.isPlaying
                                ? language.text("Playing…", "Reproduciendo…")
                                : (playbackCount == 0
                                    ? language.text("Play sentence", "Reproducir frase")
                                    : language.text("Replay once", "Repetir una vez")),
                            systemImage: "play.circle.fill"
                        )
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(audio.isPlaying || playbackCount >= 2)

                    TextField(language.text("Type what you heard", "Escribe lo que oíste"), text: $response, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    AudioErrorText(message: audio.lastError)

                    Button(language.text("Submit answer", "Enviar respuesta"), action: submitCurrentResponse)
                        .buttonStyle(.bordered)
                        .disabled(playbackCount == 0 || response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || audio.isPlaying)
                }
            }

            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "eye.slash.fill").foregroundStyle(.indigo)
                    Text(language.text(
                        "No correctness feedback is shown during the run. This limits learning and expectation differences between blocks.",
                        "No se muestra corrección durante la prueba. Esto reduce diferencias de aprendizaje y expectativa entre bloques."
                    ))
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var breakContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Block 1 complete", "Bloque 1 completado"), systemImage: "pause.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.cyan)
                Text(language.text(
                    "Take a short break. Keep the headset, device volume, and listening mode unchanged. The second condition remains hidden.",
                    "Haz una pausa breve. No cambies auriculares, volumen ni modo de escucha. La segunda condición sigue oculta."
                ))
                .foregroundStyle(.secondary)
                Button(action: continueAfterBreak) {
                    Label(language.text("Begin block 2", "Iniciar bloque 2"), systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var completionContent: some View {
        Group {
            if let savedTest {
                SpeechEQComparisonSummary(test: savedTest, language: language)
                SpeechComparisonFilterCard(
                    bands: savedTest.bands.map { StereoCompensationBand(frequency: $0.frequency, leftGainDB: $0.leftGainDB, rightGainDB: $0.rightGainDB) },
                    maximumBoostDB: savedTest.maximumBoostDB,
                    language: language
                )
            }
            Button(action: reset) {
                Label(language.text("Run another comparison", "Hacer otra comparación"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func setupMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func startTest() {
        setupError = nil
        guard let pureToneTest = selectedPureToneTest else {
            setupError = language.text("Select a bilateral audiogram first.", "Selecciona primero un audiograma bilateral.")
            return
        }
        do {
            let status = try AudioSessionManager.shared.outputRouteStatus()
            routeStatus = status
            guard status.isReadyForBilateralTest else {
                setupError = language.text(
                    "Connect stereo AirPods or Bose QuietComfort before starting.",
                    "Conecta AirPods o Bose QuietComfort estéreo antes de empezar."
                )
                return
            }
        } catch {
            setupError = error.localizedDescription
            return
        }

        let seed = UInt64.random(in: 1...UInt64.max)
        let candidates = model.allocateSentences(language: language, count: trialsPerCondition * 3)
        guard let generated = SpeechComparisonPlanner.makePlan(
            candidates: candidates,
            language: language,
            trialsPerCondition: trialsPerCondition,
            seed: seed
        ) else {
            setupError = language.text("Could not prepare unique matched sentences.", "No se pudieron preparar frases únicas equilibradas.")
            return
        }
        activeBands = CompensationDesigner.bands(from: pureToneTest, maximumBoostDB: maximumBoostDB)
        plan = generated
        currentIndex = 0
        recordedTrials = []
        response = ""
        playbackCount = 0
        savedTest = nil
        phase = .testing
    }

    private func playCurrentSentence() {
        guard let currentTrial else { return }
        playbackCount += 1
        responseClock = Date()
        Task {
            await audio.playSpeechComparison(
                currentTrial.sentence,
                snrDB: snrDB,
                noise: noise,
                language: language,
                voiceProfile: model.selectedVoice,
                bands: activeBands,
                eqEnabled: currentTrial.condition == .audiogramEQ,
                fixedHeadroomMaximumBoostDB: maximumBoostDB,
                noiseSeed: pairedNoiseSeed(for: currentTrial.pairIndex)
            )
        }
    }

    private func submitCurrentResponse() {
        guard let currentTrial else { return }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let score = WordScorer.score(reference: currentTrial.sentence, response: trimmed)
        recordedTrials.append(SpeechComparisonTrial(
            pairIndex: currentTrial.pairIndex,
            condition: currentTrial.condition,
            sentence: currentTrial.sentence,
            response: trimmed,
            score: score,
            responseTime: max(0, Date().timeIntervalSince(responseClock)),
            playbackCount: playbackCount,
            complexity: currentTrial.complexity
        ))
        response = ""
        playbackCount = 0
        currentIndex += 1
        if currentIndex == trialsPerCondition {
            phase = .betweenBlocks
        } else if currentIndex >= totalTrials {
            finishTest()
        }
    }

    private func continueAfterBreak() {
        response = ""
        playbackCount = 0
        phase = .testing
    }

    private func finishTest() {
        guard let plan, let pureToneTest = selectedPureToneTest else { return }
        let test = SpeechEQComparisonTest(
            id: UUID(),
            name: testName,
            date: Date(),
            language: language,
            voiceProfile: model.selectedVoice,
            resolvedVoiceName: audio.lastResolvedVoiceName,
            noise: noise,
            snrDB: snrDB,
            pureToneTestID: pureToneTest.id,
            pureToneTestName: pureToneTest.name,
            pureToneRouteName: pureToneTest.outputRouteName,
            maximumBoostDB: maximumBoostDB,
            bands: activeBands.map { SpeechComparisonBand(frequency: $0.frequency, leftGainDB: $0.leftGainDB, rightGainDB: $0.rightGainDB) },
            blockOrder: plan.blockOrder,
            planSeed: plan.seed,
            trials: recordedTrials
        )
        savedTest = model.saveSpeechEQComparison(test)
        audio.stop()
        phase = .complete
    }

    private func reset() {
        audio.stop()
        testName = model.defaultTestName(for: .speechEQComparison, language: language)
        phase = .setup
        plan = nil
        currentIndex = 0
        response = ""
        playbackCount = 0
        recordedTrials = []
        activeBands = []
        savedTest = nil
        setupError = nil
        snrDB = min(12, max(-5, model.profile.snr80))
        refreshRoute()
    }

    private func refreshRoute() {
        do {
            routeStatus = try AudioSessionManager.shared.outputRouteStatus()
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func normalizeMeasurementSelection() {
        if selectedPureToneSource != "latest",
           !pureToneRecords.contains(where: { $0.id.uuidString == selectedPureToneSource }) {
            selectedPureToneSource = "latest"
        }
    }

    private func pairedNoiseSeed(for pairIndex: Int) -> UInt64 {
        let base = plan?.seed ?? 1
        return base ^ (UInt64(pairIndex + 1) &* 0xD1B54A32D192ED03)
    }

    private func recordOptionLabel(_ record: TestRecord) -> String {
        "\(record.name) · \(record.date.formatted(date: .numeric, time: .shortened))"
    }
}

private enum ComparisonPhase {
    case setup
    case testing
    case betweenBlocks
    case complete
}

struct SpeechEQComparisonSummary: View {
    let test: SpeechEQComparisonTest
    let language: TestLanguage

    private var chartData: [ConditionScore] {
        [
            ConditionScore(name: test.language.text("Standard", "Estándar"), score: test.standardMeanScore * 100, color: .gray),
            ConditionScore(name: "EQ", score: test.equalizedMeanScore * 100, color: .green)
        ]
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Comparison complete", "Comparación completada"), systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.green)
                Text(test.name).font(.headline)

                HStack(spacing: 10) {
                    SmallMetric(title: language.text("Standard", "Estándar"), value: "\(Int((test.standardMeanScore * 100).rounded()))", unit: "%", color: .gray)
                    SmallMetric(title: "Audiogram EQ", value: "\(Int((test.equalizedMeanScore * 100).rounded()))", unit: "%", color: .green)
                    SmallMetric(title: language.text("Difference", "Diferencia"), value: String(format: "%+.0f", test.differencePercentagePoints), unit: "pp", color: test.differencePercentagePoints >= 0 ? .cyan : .orange)
                }

                Chart(chartData) { item in
                    BarMark(x: .value("Condition", item.name), y: .value("Recognition", item.score))
                        .foregroundStyle(item.color.gradient)
                        .cornerRadius(7)
                    RuleMark(y: .value("Maximum", 100)).foregroundStyle(.white.opacity(0.15))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 220)

                if let interval = test.pairedConfidenceInterval95 {
                    LabeledContent(
                        language.text("Approx. paired 95% interval", "Intervalo pareado aprox. del 95%"),
                        value: String(format: "%+.1f to %+.1f pp", interval.lowerBound, interval.upperBound)
                    )
                    .font(.footnote)
                }
                LabeledContent(
                    language.text("Block order", "Orden de bloques"),
                    value: test.blockOrder.map { $0.displayName(in: language) }.joined(separator: " → ")
                )
                .font(.footnote)
                LabeledContent(language.text("Fixed SNR", "SNR fijo"), value: "\(signed(test.snrDB)) dB")
                    .font(.footnote)

                Divider()
                Text(language.text("Material balance check", "Control de equilibrio del material")).font(.headline)
                LabeledContent(language.text("Mean word-count difference", "Diferencia media de palabras"), value: String(format: "%+.2f", test.wordCountDifference))
                LabeledContent(language.text("Mean letter-count difference", "Diferencia media de letras"), value: String(format: "%+.2f", test.letterCountDifference))
                LabeledContent(language.text("Mean vowel-group difference", "Diferencia media de grupos vocálicos"), value: String(format: "%+.2f", test.vowelGroupDifference))
                LabeledContent(language.text("Maximum shared content words in a pair", "Máximo de palabras de contenido compartidas"), value: "\(test.maximumSharedContentWordsPerPair)")
                Text(language.text(
                    "A positive difference means higher word recognition with EQ in this run. The interval is descriptive, uses only 12 matched pairs, and is not evidence of clinical efficacy.",
                    "Una diferencia positiva indica mayor reconocimiento con EQ en esta prueba. El intervalo es descriptivo, usa solo 12 pares y no demuestra eficacia clínica."
                ))
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeechComparisonFilterCard: View {
    let bands: [StereoCompensationBand]
    let maximumBoostDB: Double
    let language: TestLanguage

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(language.text("Applied EQ filter", "Filtro EQ aplicado"), systemImage: "waveform.path")
                    .font(.headline)
                Chart {
                    ForEach(bands) { band in
                        LineMark(x: .value("Frequency", band.frequency), y: .value("Left", band.leftGainDB), series: .value("Ear", "Left"))
                            .foregroundStyle(.blue)
                        PointMark(x: .value("Frequency", band.frequency), y: .value("Left", band.leftGainDB))
                            .foregroundStyle(.blue)
                        LineMark(x: .value("Frequency", band.frequency), y: .value("Right", band.rightGainDB), series: .value("Ear", "Right"))
                            .foregroundStyle(.red)
                        PointMark(x: .value("Frequency", band.frequency), y: .value("Right", band.rightGainDB))
                            .foregroundStyle(.red)
                    }
                }
                .chartXScale(type: .log)
                .chartYScale(domain: 0...max(2, maximumBoostDB))
                .frame(height: 210)
                HStack(spacing: 16) {
                    Label(language.text("Left", "Izquierdo"), systemImage: "circle.fill").foregroundStyle(.blue)
                    Label(language.text("Right", "Derecho"), systemImage: "circle.fill").foregroundStyle(.red)
                }
                .font(.caption.bold())
                Text(language.text(
                    "Smoothed half-gain compensation is calculated independently for each ear and limited to \(Int(maximumBoostDB)) dB.",
                    "La compensación suavizada de media ganancia se calcula por separado para cada oído y se limita a \(Int(maximumBoostDB)) dB."
                ))
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConditionScore: Identifiable {
    let id = UUID()
    let name: String
    let score: Double
    let color: Color
}
