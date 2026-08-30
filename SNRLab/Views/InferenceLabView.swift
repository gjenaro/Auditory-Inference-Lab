import SwiftUI
import Charts
import Combine

struct InferenceLabView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var audio = PersonalizedAudioEngine()

    @AppStorage("auditoryinference.lab.pureToneSource.v1") private var selectedPureToneSource = "latest"
    @AppStorage("auditoryinference.lab.speechSource.v1") private var selectedSpeechSource = "latest"
    @AppStorage("auditoryinference.lab.predictiveSource.v1") private var selectedPredictiveSource = "latest"
    @AppStorage("auditoryinference.lab.maximumBoost.v1") private var maximumBoostDB = 6.0

    @State private var selectedStrategy: CompensationStrategy = .inferenceVerified
    @State private var selectedTrack = DemoTrack.catalog[0]
    @State private var experiment: PersonalizationExperiment?
    @State private var strategyA: CompensationStrategy = .original
    @State private var strategyB: CompensationStrategy = .audiogram
    @State private var auditionedChoice: BlindComparisonChoice?
    @State private var lastReveal: String?
    @State private var scrubberTime = 0.0
    @State private var isScrubbing = false

    private let playbackTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let comparisonPairs: [(CompensationStrategy, CompensationStrategy)] = [
        (.original, .audiogram),
        (.original, .speechAware),
        (.original, .inferenceVerified),
        (.audiogram, .speechAware),
        (.audiogram, .inferenceVerified),
        (.speechAware, .inferenceVerified)
    ]

    private var language: TestLanguage { model.selectedLanguage }
    private var pureToneRecords: [TestRecord] {
        model.history.filter { $0.kind == .frequency && $0.pureToneTest != nil }
    }
    private var speechRecords: [TestRecord] {
        model.history.filter { $0.kind == .speechInNoise && $0.snr50 != nil }
    }
    private var predictiveRecords: [TestRecord] {
        model.history.filter { $0.kind == .predictiveListening && $0.predictiveTest != nil }
    }

    private var selectedPureToneRecord: TestRecord? {
        if selectedPureToneSource == "latest" { return pureToneRecords.first }
        return pureToneRecords.first { $0.id.uuidString == selectedPureToneSource }
    }
    private var selectedSpeechRecord: TestRecord? {
        if selectedSpeechSource == "latest" { return speechRecords.first }
        return speechRecords.first { $0.id.uuidString == selectedSpeechSource }
    }
    private var selectedPredictiveRecord: TestRecord? {
        if selectedPredictiveSource == "latest" { return predictiveRecords.first }
        return predictiveRecords.first { $0.id.uuidString == selectedPredictiveSource }
    }

    private var selectedPureToneTest: BilateralPureToneTest? {
        selectedPureToneRecord?.pureToneTest ?? (selectedPureToneSource == "latest" ? model.profile.latestPureToneTest : nil)
    }
    private var selectedSpeechSNR50: Double? {
        selectedSpeechRecord?.snr50 ?? (model.profile.speechTestPoints.isEmpty ? nil : model.profile.snr50)
    }
    private var selectedSpeechTrialCount: Int {
        selectedSpeechRecord?.speechPoints.count ?? model.profile.speechTestPoints.count
    }
    private var selectedPredictiveTest: PredictiveListeningTest? {
        selectedPredictiveRecord?.predictiveTest ?? (selectedPredictiveSource == "latest" ? model.profile.latestPredictiveTest : nil)
    }

    private var inferenceProfile: AuditoryInferenceProfile {
        AuditoryInferenceProfile.derive(
            pureToneTest: selectedPureToneTest,
            speechSNR50: selectedSpeechSNR50,
            speechTrialCount: selectedSpeechTrialCount,
            speechDate: selectedSpeechRecord?.date,
            predictiveTest: selectedPredictiveTest
        )
    }

    private var displayedBands: [InferenceCompensationBand] {
        designedBands(for: selectedStrategy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                measurementSourcesCard
                multidimensionalProfileCard
                candidateFilterCard
                blindLabCard
                longitudinalCard
                experimentHistoryCard
                limitationsCard
            }
            .padding()
        }
        .background(Color.black)
        .navigationTitle(language.text("Inference Lab", "Laboratorio de inferencia"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizeSelections()
            startNewExperiment()
            loadTrack()
        }
        .onDisappear { audio.stop() }
        .onChange(of: selectedTrack) { _, _ in loadTrack() }
        .onChange(of: selectedStrategy) { _, _ in applyDisplayedStrategy() }
        .onChange(of: maximumBoostDB) { _, _ in
            applyDisplayedStrategy()
            startNewExperiment()
        }
        .onChange(of: selectedPureToneSource) { _, _ in measurementsChanged() }
        .onChange(of: selectedSpeechSource) { _, _ in measurementsChanged() }
        .onChange(of: selectedPredictiveSource) { _, _ in measurementsChanged() }
        .onChange(of: model.history) { _, _ in
            normalizeSelections()
            applyDisplayedStrategy()
        }
        .onReceive(playbackTimer) { _ in audio.refreshTime() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.indigo.opacity(0.20))
                        .frame(width: 64, height: 64)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                Spacer()
                Text("RESEARCH PROTOTYPE")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            Text(language.text("Auditory Inference Lab", "Laboratorio de Inferencia Auditiva"))
                .font(.largeTitle.bold())
            Text(language.text(
                "Measure → model → compare → learn. Build a multidimensional listening profile, inspect uncertainty, and test filter candidates without knowing which one is active.",
                "Mide → modela → compara → aprende. Crea un perfil auditivo multidimensional, revisa la incertidumbre y prueba filtros sin saber cuál está activo."
            ))
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var measurementSourcesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Measurements used", "Mediciones utilizadas"), systemImage: "tray.full.fill")
                    .font(.headline)
                Text(language.text(
                    "Each menu selects a saved protocol. The app preserves the modules as separate evidence sources instead of mixing their physical units.",
                    "Cada menú selecciona un protocolo guardado. La app conserva los módulos como fuentes separadas y no mezcla sus unidades físicas."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                sourcePicker(
                    title: language.text("Bilateral tone profile", "Perfil tonal bilateral"),
                    symbol: "waveform.path.ecg",
                    selection: $selectedPureToneSource,
                    records: pureToneRecords
                )
                sourcePicker(
                    title: language.text("Speech in noise", "Habla con ruido"),
                    symbol: "person.wave.2.fill",
                    selection: $selectedSpeechSource,
                    records: speechRecords
                )
                sourcePicker(
                    title: language.text("Predictive listening", "Escucha predictiva"),
                    symbol: "brain.head.profile",
                    selection: $selectedPredictiveSource,
                    records: predictiveRecords
                )

                HStack(spacing: 10) {
                    MeasurementStatus(
                        title: language.text("Complete", "Completo"),
                        value: "\(Int(inferenceProfile.completeness.rounded()))%",
                        ready: inferenceProfile.completeness >= 99
                    )
                    MeasurementStatus(
                        title: language.text("Evidence", "Evidencia"),
                        value: "\(Int(inferenceProfile.evidenceConfidence.rounded()))%",
                        ready: inferenceProfile.evidenceConfidence >= 75
                    )
                }

                if inferenceProfile.completeness < 99 {
                    NavigationLink(destination: TestHubView()) {
                        Label(
                            language.text("Complete missing measurements", "Completar mediciones pendientes"),
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var multidimensionalProfileCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Multidimensional profile", "Perfil multidimensional"), systemImage: "circle.hexagongrid.fill")
                    .font(.headline)

                if inferenceProfile.metrics.isEmpty {
                    ContentUnavailableView(
                        language.text("No evidence selected", "No hay evidencia seleccionada"),
                        systemImage: "chart.bar.xaxis",
                        description: Text(language.text(
                            "Run at least one listening protocol to begin.",
                            "Realiza al menos un protocolo auditivo para empezar."
                        ))
                    )
                } else {
                    ForEach(inferenceProfile.metrics) { metric in
                        InferenceMetricRow(metric: metric, language: language)
                    }
                }

                Text(language.text(
                    "Scores are bounded visual summaries inside this app. Raw values remain visible; no score is an age norm, diagnosis, or measure of intelligence.",
                    "Las puntuaciones son resúmenes visuales internos. Los valores originales siguen visibles; ninguna puntuación es una norma por edad, diagnóstico ni medida de inteligencia."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var candidateFilterCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(language.text("Candidate filter", "Filtro candidato"), systemImage: "slider.horizontal.3")
                    .font(.headline)

                Picker(language.text("Strategy", "Estrategia"), selection: $selectedStrategy) {
                    ForEach(CompensationStrategy.allCases) { strategy in
                        Text(strategy.displayName(in: language)).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .tint(.cyan)

                Text(selectedStrategy.shortDescription(in: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(language.text("Maximum proposed gain", "Ganancia máxima propuesta"))
                        .font(.caption.bold())
                    Spacer()
                    Text("\(Int(maximumBoostDB.rounded())) dB")
                        .font(.headline)
                        .foregroundStyle(maximumBoostDB > 10 ? .orange : .green)
                }
                Slider(value: $maximumBoostDB, in: 0...20, step: 1)
                    .tint(.green)
                HStack {
                    Text("0 dB")
                    Spacer()
                    Text("20 dB")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Chart {
                    ForEach(displayedBands) { band in
                        RuleMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            yStart: .value("Left low", max(0, band.leftGainDB - band.leftUncertaintyDB)),
                            yEnd: .value("Left high", min(20, band.leftGainDB + band.leftUncertaintyDB))
                        )
                        .foregroundStyle(.blue.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round))

                        RuleMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            yStart: .value("Right low", max(0, band.rightGainDB - band.rightUncertaintyDB)),
                            yEnd: .value("Right high", min(20, band.rightGainDB + band.rightUncertaintyDB))
                        )
                        .foregroundStyle(.red.opacity(0.24))
                        .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round))

                        LineMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            y: .value("Left", band.leftGainDB),
                            series: .value("Ear", "Left")
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        PointMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            y: .value("Left", band.leftGainDB)
                        )
                        .foregroundStyle(.blue)

                        LineMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            y: .value("Right", band.rightGainDB),
                            series: .value("Ear", "Right")
                        )
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        PointMark(
                            x: .value("Frequency", frequencyLabel(band.frequency)),
                            y: .value("Right", band.rightGainDB)
                        )
                        .foregroundStyle(.red)
                    }
                    RuleMark(y: .value("Flat", 0)).foregroundStyle(.white.opacity(0.3))
                }
                .chartYScale(domain: 0...20)
                .chartYAxis {
                    AxisMarks(values: [0.0, 5.0, 10.0, 15.0, 20.0]) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f dB", number))
                            }
                        }
                    }
                }
                .frame(height: 230)

                HStack(spacing: 15) {
                    Label(language.text("Left", "Izquierdo"), systemImage: "circle.fill").foregroundStyle(.blue)
                    Label(language.text("Right", "Derecho"), systemImage: "circle.fill").foregroundStyle(.red)
                    Label(language.text("Uncertainty", "Incertidumbre"), systemImage: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.bold())

                Text(language.text(
                    "The translucent ranges show model uncertainty. Gain is capped, smoothed, separated by ear, and attenuated for digital headroom.",
                    "Los rangos translúcidos muestran la incertidumbre. La ganancia está limitada, suavizada, separada por oído y atenuada para conservar margen digital."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var blindLabCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(language.text("Blinded listening lab", "Laboratorio de escucha ciega"), systemImage: "eye.slash.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(experiment?.trials.count ?? 0)/6+")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }

                Text(language.text(
                    "A and B conceal the active strategies. Keep the iPhone volume fixed, switch while the same music is playing, and choose the clearer, more natural version—or no difference.",
                    "A y B ocultan las estrategias. Mantén fijo el volumen, cambia mientras suena la misma música y elige la versión más clara y natural, o ninguna diferencia."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Picker(language.text("Track", "Pista"), selection: $selectedTrack) {
                    ForEach(DemoTrack.catalog) { track in
                        Text(track.title).tag(track)
                    }
                }
                .pickerStyle(.menu)
                .tint(.green)

                VStack(alignment: .leading, spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubberTime : audio.currentTime },
                            set: { scrubberTime = $0 }
                        ),
                        in: 0...max(1, audio.duration),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing { audio.seek(to: scrubberTime) }
                        }
                    )
                    HStack {
                        Text(timeString(isScrubbing ? scrubberTime : audio.currentTime))
                        Spacer()
                        Text(timeString(audio.duration > 0 ? audio.duration : selectedTrack.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Button {
                    audio.togglePlayback()
                } label: {
                    Label(
                        audio.isPlaying ? language.text("Pause music", "Pausar música") : language.text("Play music", "Reproducir música"),
                        systemImage: audio.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(audio.loadedTrackID == nil)

                HStack(spacing: 12) {
                    auditionButton(label: "A", choice: .a, strategy: strategyA)
                    auditionButton(label: "B", choice: .b, strategy: strategyB)
                }

                Text(language.text("Which version do you prefer?", "¿Qué versión prefieres?"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    preferenceButton(label: "A", choice: .a)
                    preferenceButton(
                        label: language.text("No difference", "Sin diferencia"),
                        choice: .noDifference
                    )
                    preferenceButton(label: "B", choice: .b)
                }

                if let lastReveal {
                    Label(lastReveal, systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let experiment, let recommendation = experiment.recommendedStrategy {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Current preference signal", "Señal de preferencia actual"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(recommendation.displayName(in: language))
                            .font(.title3.bold())
                            .foregroundStyle(.cyan)
                        Text(String(format: language.text(
                            "Selected in %.0f%% of its non-tie comparisons. This is personal preference evidence, not proof of clinical benefit.",
                            "Seleccionado en %.0f%% de sus comparaciones sin empate. Es evidencia de preferencia personal, no prueba de beneficio clínico."
                        ), experiment.recommendationEvidence))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan.opacity(0.08)))
                }

                HStack {
                    Text(language.text(
                        "Equal master headroom is used for A and B to reduce loudness bias.",
                        "A y B usan el mismo margen maestro para reducir el sesgo por volumen."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(language.text("New run", "Nueva serie")) { startNewExperiment() }
                        .font(.caption.bold())
                }

                AudioErrorText(message: audio.errorMessage)
            }
        }
    }

    private var longitudinalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                Label(language.text("Change over time", "Cambio con el tiempo"), systemImage: "clock.arrow.2.circlepath")
                    .font(.headline)

                if pureToneRecords.count < 2 && speechRecords.count < 2 && predictiveRecords.count < 2 {
                    Text(language.text(
                        "Repeat a protocol on a later date to compare the latest and previous saved results.",
                        "Repite un protocolo en otra fecha para comparar los resultados guardados más recientes."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    if pureToneRecords.count >= 2,
                       let current = pureToneRecords[0].pureToneTest,
                       let previous = pureToneRecords[1].pureToneTest {
                        changeRow(
                            title: language.text("Tone profile", "Perfil tonal"),
                            value: String(format: "%.1f units", averageThresholdChange(current: current, previous: previous)),
                            detail: language.text("Mean absolute left/right change", "Cambio absoluto medio de ambos oídos")
                        )
                    }
                    if speechRecords.count >= 2,
                       let current = speechRecords[0].snr50,
                       let previous = speechRecords[1].snr50 {
                        changeRow(
                            title: "SNR50",
                            value: String(format: "%+.1f dB", current - previous),
                            detail: language.text("Latest minus previous", "Último menos anterior")
                        )
                    }
                    if predictiveRecords.count >= 2,
                       let current = predictiveRecords[0].predictiveTest,
                       let previous = predictiveRecords[1].predictiveTest {
                        changeRow(
                            title: language.text("Context benefit", "Beneficio del contexto"),
                            value: String(format: "%+.0f pp", current.contextBenefit - previous.contextBenefit),
                            detail: language.text("Latest minus previous", "Último menos anterior")
                        )
                        changeRow(
                            title: language.text("Adaptation gain", "Ganancia de adaptación"),
                            value: String(format: "%+.0f pp", current.adaptationGain - previous.adaptationGain),
                            detail: language.text("Latest minus previous", "Último menos anterior")
                        )
                    }
                }

                Text(language.text(
                    "Differences can reflect learning, attention, fit, environment, device mode, or random variation. They are not evidence of medical change.",
                    "Las diferencias pueden reflejar aprendizaje, atención, ajuste, ambiente, modo del dispositivo o variación aleatoria. No prueban un cambio médico."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var experimentHistoryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(language.text("Saved blind runs", "Series ciegas guardadas"), systemImage: "archivebox.fill")
                    .font(.headline)
                if model.personalizationExperiments.isEmpty {
                    Text(language.text(
                        "Your choices will be stored locally after the first comparison.",
                        "Tus elecciones se guardarán localmente después de la primera comparación."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(model.personalizationExperiments.prefix(5)) { saved in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(saved.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline.bold())
                                Text("\(saved.trials.count) " + language.text("comparisons", "comparaciones"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let recommendation = saved.recommendedStrategy {
                                Label(recommendation.displayName(in: language), systemImage: recommendation.symbol)
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                            } else {
                                Text(language.text("Collecting", "Recopilando"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if saved.id != model.personalizationExperiments.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var limitationsCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(language.text(
                    "Research prototype only. It is not a hearing aid, clinical audiogram, medical device, treatment, or diagnostic test. Start at low volume. Results and filters depend on the headphones, fit, route, device mode, ambient noise, attention, and uncalibrated output.",
                    "Solo es un prototipo de investigación. No es un audífono, audiograma clínico, dispositivo médico, tratamiento ni prueba diagnóstica. Empieza con volumen bajo. Los resultados dependen de los auriculares, ajuste, ruta, modo, ruido, atención y salida sin calibrar."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func sourcePicker(
        title: String,
        symbol: String,
        selection: Binding<String>,
        records: [TestRecord]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(language.text("Latest saved result", "Último resultado guardado")).tag("latest")
                ForEach(records) { record in
                    Text(recordLabel(record)).tag(record.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            .tint(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }

    private func auditionButton(
        label: String,
        choice: BlindComparisonChoice,
        strategy: CompensationStrategy
    ) -> some View {
        Button {
            auditionedChoice = choice
            apply(strategy: strategy)
            if !audio.isPlaying { audio.togglePlayback() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: auditionedChoice == choice ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                Text(language.text("Listen ", "Escuchar ") + label).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(auditionedChoice == choice ? Color.black : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(auditionedChoice == choice ? Color.cyan : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedPureToneTest == nil || audio.loadedTrackID == nil)
    }

    private func preferenceButton(label: String, choice: BlindComparisonChoice) -> some View {
        Button(label) { recordPreference(choice) }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            .buttonStyle(.plain)
            .disabled(auditionedChoice == nil || selectedPureToneTest == nil)
    }

    private func changeRow(title: String, value: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.cyan)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
    }

    private func designedBands(for strategy: CompensationStrategy) -> [InferenceCompensationBand] {
        InferenceCompensationDesigner.bands(
            strategy: strategy,
            pureToneTest: selectedPureToneTest,
            speechSNR50: selectedSpeechSNR50,
            predictiveTest: selectedPredictiveTest,
            maximumBoostDB: maximumBoostDB
        )
    }

    private func loadTrack() {
        audio.load(
            track: selectedTrack,
            bands: designedBands(for: selectedStrategy).map(\.stereoBand),
            fixedHeadroomMaximumBoostDB: maximumBoostDB
        )
        audio.setCompensated(selectedStrategy != .original)
        scrubberTime = 0
        auditionedChoice = nil
    }

    private func applyDisplayedStrategy() {
        apply(strategy: selectedStrategy)
    }

    private func apply(strategy: CompensationStrategy) {
        audio.updateBands(
            designedBands(for: strategy).map(\.stereoBand),
            fixedHeadroomMaximumBoostDB: maximumBoostDB
        )
        audio.setCompensated(strategy != .original)
    }

    private func measurementsChanged() {
        normalizeSelections()
        startNewExperiment()
        applyDisplayedStrategy()
    }

    private func startNewExperiment() {
        experiment = PersonalizationExperiment(
            pureToneTestID: selectedPureToneTest?.id,
            speechTestID: selectedSpeechRecord?.id,
            predictiveTestID: selectedPredictiveTest?.id
        )
        lastReveal = nil
        prepareNextPair(trialNumber: 0)
    }

    private func prepareNextPair(trialNumber: Int) {
        let pair = comparisonPairs[trialNumber % comparisonPairs.count]
        if Bool.random() {
            strategyA = pair.0
            strategyB = pair.1
        } else {
            strategyA = pair.1
            strategyB = pair.0
        }
        auditionedChoice = nil
    }

    private func recordPreference(_ choice: BlindComparisonChoice) {
        guard var current = experiment else { return }
        let trial = BlindComparisonTrial(
            trackID: selectedTrack.id,
            strategyA: strategyA,
            strategyB: strategyB,
            choice: choice,
            maximumBoostDB: maximumBoostDB
        )
        current.record(trial)
        experiment = current
        model.upsertPersonalizationExperiment(current)

        lastReveal = language.text(
            "Choice saved. A/B labels were randomized again.",
            "Elección guardada. Las etiquetas A/B se volvieron a aleatorizar."
        )
        prepareNextPair(trialNumber: current.trials.count)
    }

    private func normalizeSelections() {
        if selectedPureToneSource != "latest",
           !pureToneRecords.contains(where: { $0.id.uuidString == selectedPureToneSource }) {
            selectedPureToneSource = "latest"
        }
        if selectedSpeechSource != "latest",
           !speechRecords.contains(where: { $0.id.uuidString == selectedSpeechSource }) {
            selectedSpeechSource = "latest"
        }
        if selectedPredictiveSource != "latest",
           !predictiveRecords.contains(where: { $0.id.uuidString == selectedPredictiveSource }) {
            selectedPredictiveSource = "latest"
        }
    }

    private func averageThresholdChange(
        current: BilateralPureToneTest,
        previous: BilateralPureToneTest
    ) -> Double {
        let values = HearingEar.allCases.flatMap { ear in
            CompensationDesigner.frequencies.compactMap { frequency -> Double? in
                guard let currentValue = current.threshold(for: ear, frequency: frequency)?.finalRelativeThreshold,
                      let previousValue = previous.threshold(for: ear, frequency: frequency)?.finalRelativeThreshold else { return nil }
                return abs(currentValue - previousValue)
            }
        }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func recordLabel(_ record: TestRecord) -> String {
        "\(record.name) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        frequency >= 1_000
            ? String(format: "%.0fk", frequency / 1_000)
            : String(format: "%.0f", frequency)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct InferenceMetricRow: View {
    let metric: AuditoryInferenceMetric
    let language: TestLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(metric.kind.displayName(in: language), systemImage: metric.kind.symbol)
                    .font(.subheadline.bold())
                Spacer()
                Text(rawLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: metric.score, total: 100)
                .tint(metric.evidenceReliability >= 75 ? .cyan : .orange)
            HStack {
                Text(language.text("Display score", "Puntuación visual") + " \(Int(metric.score.rounded()))")
                Spacer()
                Text(language.text("evidence", "evidencia") + " \(Int(metric.evidenceReliability.rounded()))%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
    }

    private var rawLabel: String {
        if metric.rawUnit == "%" || metric.rawUnit == "pp" || metric.rawUnit == "% intrusions" {
            return String(format: "%.0f %@", metric.rawValue, metric.rawUnit)
        }
        return String(format: "%.1f %@", metric.rawValue, metric.rawUnit)
    }
}
