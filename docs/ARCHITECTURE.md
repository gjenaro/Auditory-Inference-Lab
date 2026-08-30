# Architecture

## Design goals

Auditory Inference Lab is structured as a local-first SwiftUI application with five engineering
priorities:

1. Keep pure-tone, speech-in-noise, predictive-listening, volume, and
   environmental measurements as separate domains.
2. Preserve raw behavioral observations, not only summary values.
3. Route left and right signals explicitly so a bilateral result never collapses
   into one threshold curve.
4. Leave calibration, masking, external transducers, import/export, and clinical
   reporting as explicit extension points rather than pretending they exist.
5. Treat personalization as candidate generation plus blinded verification, not
   as a one-formula prescription.

The current implementation is intentionally small: one application target, no
third-party packages, no server, and no dependency-injection framework.

## System context

```mermaid
flowchart LR
    Person["Listener"]
    App["Auditory Inference Lab"]
    Mic["iPhone or Bluetooth microphone"]
    Output["Supported stereo Bluetooth headset / audio output"]
    OS["iOS audio routing and installed voices"]
    Local["Local UserDefaults storage"]

    Person -->|taps and typed words| App
    Mic -->|PCM buffers| App
    App -->|speech, noise, and tones| Output
    OS -->|route, channels, voices| App
    App <--> Local
```

The application does not control headset firmware, noise-control mode, system
volume, acoustic coupling, or Bluetooth processing. It asks the listener to keep
those conditions stable and records only the route information exposed by iOS.

## Source layout and responsibilities

| Path | Responsibility |
| --- | --- |
| `SNRLab/App/AuditoryInferenceLabApp.swift` | App entry point, root `AppModel`, forced dark appearance |
| `SNRLab/App/AppModel.swift` | Observable state, test naming, record creation, JSON persistence |
| `SNRLab/Models/Models.swift` | Codable domain records, staircase, word scorer, sigmoid fit, bootstrap |
| `SNRLab/Models/PredictiveModels.swift` | Predictive-listening trial protocol, bilingual materials, metrics, and Codable result models |
| `SNRLab/Models/InferenceModels.swift` | Multidimensional transforms, evidence/uncertainty, filter candidates, blinded-trial records and recommendation rule |
| `SNRLab/Audio/AudioEngines.swift` | Audio sessions, route inspection, microphone estimator, synthesis, test stimuli |
| `SNRLab/Audio/PersonalizedAudioEngine.swift` | Music catalog, stereo channel split, independent EQ, playback and headroom |
| `SNRLab/Views/MainViews.swift` | Root tabs, live display, results, audiograms, history, settings |
| `SNRLab/Views/TestViews.swift` | Test hub and behavioral test workflows |
| `SNRLab/Views/PredictiveListeningView.swift` | Four-stage predictive-listening workflow, progress UI, response capture, and summary chart |
| `SNRLab/Views/PersonalizedAudioView.swift` | Measurement selector, music player, filter graph and comparison controls |
| `SNRLab/Views/InferenceLabView.swift` | Evidence selectors, multidimensional profile, uncertainty chart, randomized A/B lab and longitudinal view |
| `SNRLab/Resources` | App metadata, icon, colors, music and license notes |

## UI composition

`RootView` contains five navigation stacks in a tab view:

- **Home**: module entry points and latest SNR summary.
- **Test**: a three-stage Complete Listening Profile guide plus independent speech
  in noise, bilateral pure tone, predictive listening, volume sensitivity, and
  noise profile modules. Guided completion is derived from the latest saved
  result in each core module; each workflow remains independently resumable.
- **Lab**: measurement-source dropdowns, multidimensional profile, candidate
  filters, blinded music comparisons, saved preference signals, and longitudinal
  summaries.
- **Results**: pure-tone profile, speech psychometric data, test-quality metrics,
  history, and entry to Personalized Audio.
- **Settings**: language, voice, audio guidance, limitations, safety, copyright,
  and data reset.

Views own short-lived workflow state with `@State` and audio engines with
`@StateObject`. Shared results and preferences live in `AppModel`, injected with
`environmentObject`.

## State and persistence

```mermaid
flowchart TD
    TestView["Test workflow state"]
    Record["Typed result\nPureToneTrial / RecognitionPoint / VolumePoint"]
    AppModel["AppModel"]
    Profile["HearingProfile\nlatest summaries"]
    History["TestRecord[ ]\nnewest first, maximum 100"]
    Experiments["PersonalizationExperiment[ ]\nnewest first, maximum 50"]
    Defaults["UserDefaults\nJSON Data values"]

    TestView --> Record --> AppModel
    AppModel --> Profile
    AppModel --> History
    AppModel --> Experiments
    Profile --> Defaults
    History --> Defaults
    Experiments --> Defaults
```

Six versioned key families are currently used:

- `auditoryinference.profile.v1`
- `auditoryinference.history.v1`
- `auditoryinference.experiments.v1`
- `auditoryinference.language.v1`
- `auditoryinference.voice.v1`
- `auditoryinference.sentence-position.v1.<language>`

The profile and history are encoded with `JSONEncoder`. The saved history is
truncated to the 100 most recent records. There is no schema migration service;
compatibility relies on custom/default decoding in the models and stable key
names.

Personalization experiments are encoded independently and truncated to the 50
most recent runs. Empty runs are not stored. See `INFERENCE_ENGINE.md` for the
candidate-design and blinded-comparison flow.

## Audio-session policy

`AudioSessionManager` centralizes two modes:

| Mode | Category | AVAudioSession mode | Use |
| --- | --- | --- | --- |
| Measurement | `playAndRecord` | `measurement` | Live SNR and room-noise estimate |
| Playback | `playback` | `default` | Speech, synthetic noise, tones, music |

Playback requests two output channels when the active route supports them.
`outputRouteStatus()` records the first output name, whether iOS classifies it as
Bluetooth, whether the route name matches AirPods or a Bose QuietComfort/QC
pattern, and the reported channel count. A route is accepted for the bilateral
test only when it matches one of those supported families and has at least two
channels. Bose matching requires a `Bose` token plus either `QuietComfort`,
`Quiet Comfort`, `QC`, or a model token such as `QC45`.

This is a practical setup guard, not hardware attestation. Public iOS APIs do not
prove that each physical earbud is inserted correctly, so the UI adds audible
left/right checks and listener confirmations.

Apple documents `AVAudioSession.outputNumberOfChannels` as the number of channels
on the current route. See [Apple's channel documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputnumberofchannels).

## Pure-tone signal path

```mermaid
flowchart LR
    State["FrequencySensitivityView\nsetup/practice/test/review/complete"]
    Stair["PureToneStaircase\nrelative level + trial log"]
    Delay["Random delay / catch decision"]
    Tone["48 kHz stereo pulsed-tone buffer"]
    L["Left sample channel"]
    R["Right sample channel"]
    Route["Supported stereo headset route"]
    Save["BilateralPureToneTest"]

    State --> Stair --> Delay
    Delay -->|real trial| Tone
    Delay -->|silent catch| State
    Tone --> L --> Route
    Tone --> R --> Route
    State -->|heard / missed / response time| Stair
    Stair -->|threshold result| Save
```

For a real trial, only the target channel receives the sinusoid; the opposite
channel is filled with zeros. The generator has an optional opposite-channel
noise parameter reserved for future experiments, but the current screening flow
always passes `nil`. This is not clinical masking.

The view rechecks the route before every presentation and pauses if the supported
stereo route disappears. The workflow is a state machine with these phases:

```text
setup → bilateral practice → left test → left review
      → right test → right review → save/complete
```

## Speech and noise path

```mermaid
flowchart LR
    Text["English/Spanish sentence"]
    Voice["Installed AVSpeechSynthesisVoice"]
    TTS["AVSpeechSynthesizer PCM buffers"]
    Norm["Active-RMS normalization"]
    Noise["Synthetic noise generator"]
    Scale["Noise scaled to target digital SNR"]
    Mix["AVAudioEngine mixer"]
    Output["Audio output"]

    Text --> Voice --> TTS --> Norm --> Mix
    Noise --> Scale --> Mix --> Output
```

Voice selection is dynamic because voice availability differs by device. The
resolver prefers a requested language and gender, ranks by Apple voice quality,
excludes novelty and Personal Voice entries, and falls back to the nearest
available language. Girl and Boy are higher-pitch simulations, not recordings of
children and not an age classification provided by Apple.

Speech is emitted as PCM buffers with `AVSpeechSynthesizer.write`. Apple describes
this API as generating speech into a buffer callback for further processing:
[speech buffer documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write%28_%3Atobuffercallback%3A%29).

Sentence material for the ordinary speech modules is generated from a 12-subject
by 12-predicate matrix in each language. `AppModel` advances a persisted modular
permutation cursor so all 144 sentences in a language are used before that
language begins another cycle. The English and Spanish cursors are independent.

## Predictive-listening path

```mermaid
flowchart LR
    Plan["PredictiveCorpus\n36 randomized trials"]
    Context["Context + misleading blocks\nvoice + selected noise at SNR80"]
    Closure["Closure block\n3 Hz silent/noise-filled gaps"]
    Adapt["Adaptation block\nconstant exploratory filter"]
    Input["Typed response\nconfidence · effort · replay count"]
    Trial["PredictiveListeningTrial"]
    Summary["Context · restoration · prediction · adaptation"]
    Store["Profile + test history"]

    Plan --> Context --> Input
    Plan --> Closure --> Input
    Plan --> Adapt --> Input
    Input --> Trial --> Summary --> Store
```

The view snapshots language, voice, noise, and the latest SNR80 when the listener
starts. The run does not reveal correctness between trials. `StimulusEngine`
creates every stimulus locally and exposes separate paths for speech in noise,
interrupted speech, and consistently filtered speech. The typed result preserves
the raw stimulus/reference text so a saved score can be audited later.

The predictive models are not fed into the pure-tone threshold curve or the
Personalized Audio EQ. See [`PREDICTIVE_LISTENING.md`](PREDICTIVE_LISTENING.md)
for the protocol and claim boundary.

## Live SNR path

`LiveSNREngine` installs a 2048-frame tap on the first microphone channel. Each
buffer becomes a full-scale-relative RMS level. A rolling window of at most 120
levels is sorted; the 20th percentile is the noise estimate and the 82nd
percentile is the signal estimate. Their difference is clamped to −10…40 dB and
published about every 160 ms.

No classifier identifies actual speech. The terms “signal” and “noise” are
therefore operational labels for upper and lower portions of recent level
activity, not isolated acoustic sources.

## Personalized Audio graph

```mermaid
flowchart LR
    File["Bundled stereo MP3/M4A"]
    Split["Temporary mono CAF split"]
    LP["Left player"]
    RP["Right player"]
    LEQ["8-band left AVAudioUnitEQ"]
    REQ["8-band right AVAudioUnitEQ"]
    LPan["Pan hard left"]
    RPan["Pan hard right"]
    Headroom["Shared headroom mixer"]
    Main["Main mixer / output"]

    File --> Split
    Split --> LP --> LEQ --> LPan --> Headroom
    Split --> RP --> REQ --> RPan --> Headroom
    Headroom --> Main
```

The source file is read in 16,384-frame chunks and split into temporary float32
mono CAF files. Mono source files are duplicated to both sides. Two synchronized
player nodes preserve channel-specific processing. Original mode bypasses both
equalizers; Compensated mode enables them. The shared downstream mixer applies
the same conservative headroom in both modes.

`AVAudioEngine` is Apple's node-graph audio system, and `AVAudioUnitEQ` exposes
frequency, gain, bandwidth, filter type, and bypass controls. See
[AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
and [EQ filter parameters](https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters/filtertype).

## Concurrency and lifecycle

- UI state and observable audio objects run on the main actor.
- Speech synthesis is exposed as `async` and returns buffers through a checked
  continuation.
- Pure-tone randomized waits and response windows use cancellable Swift tasks.
- Microphone callbacks perform buffer arithmetic, then publish on the main actor.
- Views stop their audio engine when leaving the screen.
- Each test presentation carries a UUID token so a stale task cannot complete a
  newer trial.

## Failure boundaries

Audio failures surface as user-visible messages instead of crashing the flow.
Typical failures include microphone denial, no input format, missing voice,
missing bundled audio, a non-stereo route, or a route change during testing.

Behavioral results that reach the per-frequency presentation cap are saved with
`metAscendingCriterion == false` and reduce the reliability score. They are not
silently treated as fully reliable thresholds.

## Planned extension seams

`BilateralPureToneTest` already contains optional fields for:

- a calibration profile identifier;
- a transducer model identifier;
- bone-conduction results;
- masking metadata;
- an imported-source identifier;
- a prior-test link for longitudinal comparison.

These fields are data-model hooks only. No calibration, bone conduction,
clinical masking, import, or longitudinal inference is implemented.

Likely future boundaries are:

1. Replace `UserDefaults` with a versioned database and explicit migration layer.
2. Isolate algorithms into a testable Swift package.
3. Add a calibrated transducer/output service keyed by verified device model.
4. Add export schemas without changing the internal trial log.
5. Add a validation layer that distinguishes engineering, research, and clinical
   operating modes.
- **Lab**: measurement-source dropdowns, multidimensional profile, candidate
  filters, blinded music comparisons, saved preference signals and longitudinal
  summaries.
