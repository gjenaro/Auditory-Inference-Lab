import Foundation

enum PredictiveModule: String, CaseIterable, Codable, Identifiable, Hashable {
    case semanticContext
    case auditoryClosure
    case predictionCost
    case adaptation

    var id: String { rawValue }

    func displayName(in language: TestLanguage) -> String {
        switch self {
        case .semanticContext:
            return language.text("Context benefit", "Beneficio del contexto")
        case .auditoryClosure:
            return language.text("Auditory closure", "Cierre auditivo")
        case .predictionCost:
            return language.text("Prediction cost", "Costo de predicción")
        case .adaptation:
            return language.text("Degraded-speech adaptation", "Adaptación al habla degradada")
        }
    }

    var symbol: String {
        switch self {
        case .semanticContext: return "text.bubble.fill"
        case .auditoryClosure: return "waveform.badge.minus"
        case .predictionCost: return "arrow.triangle.branch"
        case .adaptation: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum PredictiveCondition: String, Codable, Hashable {
    case highContext
    case lowContext
    case silentGap
    case noiseFilledGap
    case misleadingContext
    case filteredSpeech
}

enum PredictiveResponseMode: String, Codable, Hashable {
    case finalWord
    case fullSentence
}

struct PredictiveListeningTrial: Identifiable, Codable, Hashable {
    let id: UUID
    let module: PredictiveModule
    let condition: PredictiveCondition
    let promptID: String
    let stimulusText: String
    let referenceText: String
    let expectedIntrusionWord: String?
    let response: String
    let score: Double
    let expectedIntrusion: Bool
    let snrDB: Double?
    let noiseKind: NoiseKind?
    let responseTime: TimeInterval
    let presentationCount: Int
    let confidence: Int
    let effort: Int
    let timestamp: Date

    init(
        id: UUID = UUID(),
        module: PredictiveModule,
        condition: PredictiveCondition,
        promptID: String,
        stimulusText: String,
        referenceText: String,
        expectedIntrusionWord: String?,
        response: String,
        score: Double,
        expectedIntrusion: Bool,
        snrDB: Double?,
        noiseKind: NoiseKind?,
        responseTime: TimeInterval,
        presentationCount: Int,
        confidence: Int,
        effort: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.module = module
        self.condition = condition
        self.promptID = promptID
        self.stimulusText = stimulusText
        self.referenceText = referenceText
        self.expectedIntrusionWord = expectedIntrusionWord
        self.response = response
        self.score = score
        self.expectedIntrusion = expectedIntrusion
        self.snrDB = snrDB
        self.noiseKind = noiseKind
        self.responseTime = responseTime
        self.presentationCount = presentationCount
        self.confidence = confidence
        self.effort = effort
        self.timestamp = timestamp
    }
}

struct PredictiveListeningTest: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var date: Date
    var language: TestLanguage
    var voiceProfile: VoiceProfile
    var resolvedVoiceName: String?
    var anchorSNR80: Double
    var noiseKind: NoiseKind
    var trials: [PredictiveListeningTrial]
    var protocolVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        date: Date = Date(),
        language: TestLanguage,
        voiceProfile: VoiceProfile,
        resolvedVoiceName: String?,
        anchorSNR80: Double,
        noiseKind: NoiseKind,
        trials: [PredictiveListeningTrial],
        protocolVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.language = language
        self.voiceProfile = voiceProfile
        self.resolvedVoiceName = resolvedVoiceName
        self.anchorSNR80 = anchorSNR80
        self.noiseKind = noiseKind
        self.trials = trials
        self.protocolVersion = protocolVersion
    }

    static let expectedTrialCount = 36

    var contextHighAccuracy: Double { averageScore(condition: .highContext) * 100 }
    var contextLowAccuracy: Double { averageScore(condition: .lowContext) * 100 }
    var contextBenefit: Double { contextHighAccuracy - contextLowAccuracy }
    var silentGapAccuracy: Double { averageScore(condition: .silentGap) * 100 }
    var noiseFilledAccuracy: Double { averageScore(condition: .noiseFilledGap) * 100 }
    var restorationBenefit: Double { noiseFilledAccuracy - silentGapAccuracy }

    var predictionCost: Double {
        let lureTrials = trials.filter { $0.condition == .misleadingContext }
        guard !lureTrials.isEmpty else { return 0 }
        return Double(lureTrials.filter(\.expectedIntrusion).count) / Double(lureTrials.count) * 100
    }

    var adaptationGain: Double {
        let values = trials.filter { $0.condition == .filteredSpeech }.map(\.score)
        guard values.count >= 4 else { return 0 }
        let split = values.count / 2
        let early = values.prefix(split).reduce(0, +) / Double(split)
        let lateCount = values.count - split
        let late = values.suffix(lateCount).reduce(0, +) / Double(lateCount)
        return (late - early) * 100
    }

    var averageConfidence: Double { mean(trials.map { Double($0.confidence) }) }
    var averageEffort: Double { mean(trials.map { Double($0.effort) }) }
    var averageResponseTime: Double { mean(trials.map(\.responseTime)) }

    var reliabilityScore: Double {
        let completion = min(1, Double(trials.count) / Double(Self.expectedTrialCount))
        let implausible = trials.filter { $0.responseTime < 0.25 || $0.responseTime > 120 }.count
        let replays = trials.reduce(0) { $0 + max(0, $1.presentationCount - 1) }
        return min(100, max(0, completion * 100 - Double(implausible) * 4 - Double(replays) * 1.5))
    }

    private func averageScore(condition: PredictiveCondition) -> Double {
        let values = trials.filter { $0.condition == condition }.map(\.score)
        return mean(values)
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct PredictiveTrialPlan: Identifiable, Hashable {
    let id = UUID()
    let module: PredictiveModule
    let condition: PredictiveCondition
    let promptID: String
    let stimulusText: String
    let referenceText: String
    let expectedIntrusionWord: String?
    let responseMode: PredictiveResponseMode
}

private struct ContextPrompt {
    let id: String
    let high: String
    let low: String
    let target: String
}

private struct LurePrompt {
    let id: String
    let sentence: String
    let actual: String
    let expected: String
}

enum PredictiveCorpus {
    static func makePlan(for language: TestLanguage) -> [PredictiveTrialPlan] {
        let context = contextPrompts(for: language).shuffled().prefix(12).enumerated().map { index, prompt in
            let high = index.isMultiple(of: 2)
            return PredictiveTrialPlan(
                module: .semanticContext,
                condition: high ? .highContext : .lowContext,
                promptID: prompt.id,
                stimulusText: high ? prompt.high : prompt.low,
                referenceText: prompt.target,
                expectedIntrusionWord: nil,
                responseMode: .finalWord
            )
        }

        let closure = closureSentences(for: language).shuffled().prefix(10).enumerated().map { index, item in
            PredictiveTrialPlan(
                module: .auditoryClosure,
                condition: index.isMultiple(of: 2) ? .silentGap : .noiseFilledGap,
                promptID: item.id,
                stimulusText: item.text,
                referenceText: item.text,
                expectedIntrusionWord: nil,
                responseMode: .fullSentence
            )
        }

        let lures = lurePrompts(for: language).shuffled().prefix(6).map { prompt in
            PredictiveTrialPlan(
                module: .predictionCost,
                condition: .misleadingContext,
                promptID: prompt.id,
                stimulusText: prompt.sentence,
                referenceText: prompt.actual,
                expectedIntrusionWord: prompt.expected,
                responseMode: .finalWord
            )
        }

        let adaptation = adaptationSentences(for: language).shuffled().prefix(8).map { item in
            PredictiveTrialPlan(
                module: .adaptation,
                condition: .filteredSpeech,
                promptID: item.id,
                stimulusText: item.text,
                referenceText: item.text,
                expectedIntrusionWord: nil,
                responseMode: .fullSentence
            )
        }

        return context + closure + lures + adaptation
    }

    private static func contextPrompts(for language: TestLanguage) -> [ContextPrompt] {
        if language == .english {
            return [
                .init(id: "en-c01", high: "The baker put the bread into the oven.", low: "During the conversation they mentioned the oven.", target: "oven"),
                .init(id: "en-c02", high: "She unlocked the front door with a key.", low: "The final item they discussed was the key.", target: "key"),
                .init(id: "en-c03", high: "He poured the hot coffee into a cup.", low: "Someone quietly said the word cup.", target: "cup"),
                .init(id: "en-c04", high: "To stay dry in the rain she opened an umbrella.", low: "The object named at the end was an umbrella.", target: "umbrella"),
                .init(id: "en-c05", high: "At night the tired child slept in a bed.", low: "They eventually started talking about a bed.", target: "bed"),
                .init(id: "en-c06", high: "The gardener carefully watered every flower.", low: "The last thing on the list was a flower.", target: "flower"),
                .init(id: "en-c07", high: "The letter was sealed inside an envelope.", low: "The person finally mentioned an envelope.", target: "envelope"),
                .init(id: "en-c08", high: "We checked the time on the kitchen clock.", low: "The conversation ended with the word clock.", target: "clock"),
                .init(id: "en-c09", high: "She cut the paper with sharp scissors.", low: "The unusual object they named was scissors.", target: "scissors"),
                .init(id: "en-c10", high: "The hungry dog chewed a large bone.", low: "They spent several minutes discussing a bone.", target: "bone"),
                .init(id: "en-c11", high: "The evening train stopped at the station.", low: "The final place they considered was the station.", target: "station"),
                .init(id: "en-c12", high: "He brushed his teeth before going to bed.", low: "The body part named at the end was teeth.", target: "teeth"),
                .init(id: "en-c13", high: "The small bird built a nest.", low: "The person slowly repeated the word nest.", target: "nest"),
                .init(id: "en-c14", high: "They ate the warm soup with a spoon.", low: "The final object in the story was a spoon.", target: "spoon"),
                .init(id: "en-c15", high: "The photographer used the camera to take a picture.", low: "The group eventually discussed a picture.", target: "picture"),
                .init(id: "en-c16", high: "She wrote the short note with a pencil.", low: "The last word in the message was pencil.", target: "pencil")
            ]
        }
        return [
            .init(id: "es-c01", high: "El panadero puso el pan dentro del horno.", low: "Durante la conversación mencionaron el horno.", target: "horno"),
            .init(id: "es-c02", high: "Ella abrió la puerta principal con una llave.", low: "El último objeto que comentaron fue la llave.", target: "llave"),
            .init(id: "es-c03", high: "Él sirvió el café caliente en una taza.", low: "Alguien dijo en voz baja la palabra taza.", target: "taza"),
            .init(id: "es-c04", high: "Para no mojarse con la lluvia abrió un paraguas.", low: "El objeto nombrado al final fue un paraguas.", target: "paraguas"),
            .init(id: "es-c05", high: "Por la noche el niño cansado durmió en una cama.", low: "Finalmente comenzaron a hablar de una cama.", target: "cama"),
            .init(id: "es-c06", high: "La jardinera regó con cuidado cada flor.", low: "La última cosa de la lista era una flor.", target: "flor"),
            .init(id: "es-c07", high: "La carta quedó cerrada dentro de un sobre.", low: "La persona finalmente mencionó un sobre.", target: "sobre"),
            .init(id: "es-c08", high: "Miramos la hora en el reloj.", low: "La conversación terminó con la palabra reloj.", target: "reloj"),
            .init(id: "es-c09", high: "Ella cortó el papel con unas tijeras.", low: "El objeto extraño que nombraron fue tijeras.", target: "tijeras"),
            .init(id: "es-c10", high: "El perro hambriento mordió un hueso.", low: "Pasaron varios minutos hablando de un hueso.", target: "hueso"),
            .init(id: "es-c11", high: "El tren de la tarde paró en la estación.", low: "El último lugar que consideraron fue la estación.", target: "estación"),
            .init(id: "es-c12", high: "Él se cepilló los dientes antes de dormir.", low: "La parte del cuerpo nombrada al final fue dientes.", target: "dientes"),
            .init(id: "es-c13", high: "El pájaro pequeño construyó un nido.", low: "La persona repitió lentamente la palabra nido.", target: "nido"),
            .init(id: "es-c14", high: "Comieron la sopa caliente con una cuchara.", low: "El objeto final de la historia fue una cuchara.", target: "cuchara"),
            .init(id: "es-c15", high: "La fotógrafa usó la cámara para tomar una foto.", low: "El grupo finalmente comentó una foto.", target: "foto"),
            .init(id: "es-c16", high: "Ella escribió la nota corta con un lápiz.", low: "La última palabra del mensaje fue lápiz.", target: "lápiz")
        ]
    }

    private static func closureSentences(for language: TestLanguage) -> [(id: String, text: String)] {
        if language == .english {
            return [
                ("en-r01", "The red bicycle waited beside the garden wall."),
                ("en-r02", "A gentle breeze moved through the open window."),
                ("en-r03", "The family prepared dinner before the guests arrived."),
                ("en-r04", "Three bright lights appeared above the quiet harbor."),
                ("en-r05", "The librarian returned the book to the upper shelf."),
                ("en-r06", "Fresh snow covered the road during the night."),
                ("en-r07", "The mechanic checked the engine before the long trip."),
                ("en-r08", "A warm jacket hung behind the bedroom door."),
                ("en-r09", "The children followed the narrow trail through the forest."),
                ("en-r10", "Our favorite song played at the end of the concert."),
                ("en-r11", "The morning newspaper rested on the front steps."),
                ("en-r12", "A silver boat crossed the lake after sunrise.")
            ]
        }
        return [
            ("es-r01", "La bicicleta roja esperaba junto al muro del jardín."),
            ("es-r02", "Una brisa suave entró por la ventana abierta."),
            ("es-r03", "La familia preparó la cena antes de que llegaran los invitados."),
            ("es-r04", "Tres luces brillantes aparecieron sobre el puerto tranquilo."),
            ("es-r05", "La bibliotecaria devolvió el libro al estante superior."),
            ("es-r06", "La nieve fresca cubrió la carretera durante la noche."),
            ("es-r07", "El mecánico revisó el motor antes del viaje largo."),
            ("es-r08", "Una chaqueta abrigada colgaba detrás de la puerta."),
            ("es-r09", "Los niños siguieron el sendero estrecho por el bosque."),
            ("es-r10", "Nuestra canción favorita sonó al final del concierto."),
            ("es-r11", "El periódico de la mañana estaba en la entrada."),
            ("es-r12", "Un barco plateado cruzó el lago después del amanecer.")
        ]
    }

    private static func lurePrompts(for language: TestLanguage) -> [LurePrompt] {
        if language == .english {
            return [
                .init(id: "en-p01", sentence: "She spread the warm bread with honey.", actual: "honey", expected: "butter"),
                .init(id: "en-p02", sentence: "He wrote the note with a crayon.", actual: "crayon", expected: "pencil"),
                .init(id: "en-p03", sentence: "The cat chased the small rabbit.", actual: "rabbit", expected: "mouse"),
                .init(id: "en-p04", sentence: "For breakfast she drank cold water.", actual: "water", expected: "coffee"),
                .init(id: "en-p05", sentence: "The carpenter hit the nail with a stone.", actual: "stone", expected: "hammer"),
                .init(id: "en-p06", sentence: "At the birthday party they served soup.", actual: "soup", expected: "cake"),
                .init(id: "en-p07", sentence: "Before sleeping he left the lamp on.", actual: "on", expected: "off"),
                .init(id: "en-p08", sentence: "The soccer player kicked the ball with his knee.", actual: "knee", expected: "foot")
            ]
        }
        return [
            .init(id: "es-p01", sentence: "Ella untó el pan caliente con miel.", actual: "miel", expected: "mantequilla"),
            .init(id: "es-p02", sentence: "Él escribió la nota con un crayón.", actual: "crayón", expected: "lápiz"),
            .init(id: "es-p03", sentence: "El gato persiguió al conejo pequeño.", actual: "conejo", expected: "ratón"),
            .init(id: "es-p04", sentence: "En el desayuno ella bebió agua fría.", actual: "agua", expected: "café"),
            .init(id: "es-p05", sentence: "El carpintero golpeó el clavo con una piedra.", actual: "piedra", expected: "martillo"),
            .init(id: "es-p06", sentence: "En la fiesta de cumpleaños sirvieron sopa.", actual: "sopa", expected: "pastel"),
            .init(id: "es-p07", sentence: "Antes de dormir dejó la lámpara encendida.", actual: "encendida", expected: "apagada"),
            .init(id: "es-p08", sentence: "El futbolista pateó la pelota con la rodilla.", actual: "rodilla", expected: "pie")
        ]
    }

    private static func adaptationSentences(for language: TestLanguage) -> [(id: String, text: String)] {
        if language == .english {
            return [
                ("en-a01", "The small market opens early every Saturday."),
                ("en-a02", "We watched the clouds move across the valley."),
                ("en-a03", "Her green suitcase remained near the ticket counter."),
                ("en-a04", "The new restaurant serves lunch beside the river."),
                ("en-a05", "A short message appeared on the computer screen."),
                ("en-a06", "The afternoon meeting ended earlier than expected."),
                ("en-a07", "Two neighbors carried the table into the kitchen."),
                ("en-a08", "The museum guide described the painting in detail."),
                ("en-a09", "Our train crossed the bridge during the storm."),
                ("en-a10", "The quiet café closed just after sunset.")
            ]
        }
        return [
            ("es-a01", "El mercado pequeño abre temprano cada sábado."),
            ("es-a02", "Vimos las nubes moverse sobre el valle."),
            ("es-a03", "Su maleta verde quedó cerca del mostrador."),
            ("es-a04", "El restaurante nuevo sirve almuerzo junto al río."),
            ("es-a05", "Un mensaje corto apareció en la pantalla."),
            ("es-a06", "La reunión de la tarde terminó antes de lo esperado."),
            ("es-a07", "Dos vecinos llevaron la mesa hasta la cocina."),
            ("es-a08", "La guía del museo describió la pintura con detalle."),
            ("es-a09", "Nuestro tren cruzó el puente durante la tormenta."),
            ("es-a10", "La cafetería tranquila cerró después del atardecer.")
        ]
    }
}
