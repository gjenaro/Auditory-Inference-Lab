# Paper bibliography and evidence map

This is a curated reading list for the engineering and research concepts in SNR
Lab QC. Links resolve to the article of record or an authoritative index. The
repository does not redistribute paper PDFs. A paper's inclusion means it informs
a concept; it does not validate this app, headset, stimulus corpus, or score.

## Adaptive psychophysics and thresholds

### Levitt (1971) — adaptive staircases

Levitt, H. “Transformed Up-Down Methods in Psychoacoustics.” *Journal of the
Acoustical Society of America* 49(2B), 467–477.
[DOI 10.1121/1.1912375](https://doi.org/10.1121/1.1912375)

- **Informs:** why adaptive procedures concentrate samples near a psychometric
  transition and how response rules target different operating points.
- **Does not validate:** the app's exact clinical-style 10-down/5-up state
  machine, its stopping limits, or uncalibrated relative scale.

### Wichmann and Hill (2001) — psychometric uncertainty

Wichmann, F. A., and Hill, N. J. “The Psychometric Function: II.
Bootstrap-Based Confidence Intervals and Sampling.” *Perception & Psychophysics*
63, 1314–1329.
[DOI 10.3758/BF03194545](https://doi.org/10.3758/BF03194545)

- **Informs:** bootstrap uncertainty for fitted psychometric parameters.
- **Does not validate:** the app's small 120-resample MVP interval or compensate
  for sparse/adaptive sampling and model misspecification.

## Speech intelligibility and context

### Kalikow, Stevens, and Elliott (1977) — SPIN

Kalikow, D. N., Stevens, K. N., and Elliott, L. L. “Development of a Test of
Speech Intelligibility in Noise Using Sentence Materials with Controlled Word
Predictability.” *Journal of the Acoustical Society of America* 61(5), 1337–1351.
[DOI 10.1121/1.381436](https://doi.org/10.1121/1.381436)

- **Informs:** separating acoustic intelligibility from semantic predictability.
- **Does not validate:** SNR Lab's original sentences as normed SPIN materials
  or establish cross-language equivalence.

## Restoration, prediction, and adaptation

### Warren (1970) — perceptual restoration

Warren, R. M. “Perceptual Restoration of Missing Speech Sounds.” *Science*
167(3917), 392–393.
[DOI 10.1126/science.167.3917.392](https://doi.org/10.1126/science.167.3917.392)

- **Informs:** the behavioral phenomenon of perceiving speech content across an
  acoustically replaced segment.
- **Does not validate:** the app's periodic gating as a replication of the
  phoneme-specific experiment.

### Davis et al. (2005) — learning degraded speech

Davis, M. H., Johnsrude, I. S., Hervais-Adelman, A., Taylor, K., and McGettigan,
C. “Lexical Information Drives Perceptual Learning of Distorted Speech: Evidence
from the Comprehension of Noise-Vocoded Sentences.” *Journal of Experimental
Psychology: General* 134(2), 222–241.
[DOI 10.1037/0096-3445.134.2.222](https://doi.org/10.1037/0096-3445.134.2.222)

- **Informs:** rapid perceptual learning and lexical guidance under a stable
  distortion.
- **Does not validate:** the app's different filter, short block, or any durable
  training effect.

### Sohoglu et al. (2012) — prior knowledge and degraded speech

Sohoglu, E., Peelle, J. E., Carlyon, R. P., and Davis, M. H. “Predictive Top-Down
Integration of Prior Knowledge during Speech Perception.” *Journal of
Neuroscience* 32(25), 8443–8453.
[DOI 10.1523/JNEUROSCI.5069-11.2012](https://doi.org/10.1523/JNEUROSCI.5069-11.2012)

- **Informs:** a neural hypothesis for integrating prior knowledge with degraded
  acoustic evidence, investigated with simultaneous EEG and MEG.
- **Does not validate:** behavioral context benefit as a neural biomarker or
  prove a specific mechanism in an individual app user.

### Leonard et al. (2016) — cortical restoration of masked speech

Leonard, M. K., Baud, M. O., Sjerps, M. J., and Chang, E. F. “Perceptual
Restoration of Masked Speech in Human Cortex.” *Nature Communications* 7, 13619.
[DOI 10.1038/ncomms13619](https://doi.org/10.1038/ncomms13619)

- **Informs:** direct human cortical evidence related to restored acoustic-
  phonetic representations and preceding frontal prediction patterns in the
  studied clinical participants.
- **Does not validate:** inferring brain activity from SNR Lab's behavioral
  restoration score.

## Attention and listening effort

### Wild et al. (2012) — attention under degradation

Wild, C. J., Yusuf, A., Wilson, D. E., Peelle, J. E., Davis, M. H., and
Johnsrude, I. S. “Effortful Listening: The Processing of Degraded Speech Depends
Critically on Attention.” *Journal of Neuroscience* 32(40), 14010–14021.
[DOI 10.1523/JNEUROSCI.1528-12.2012](https://doi.org/10.1523/JNEUROSCI.1528-12.2012)

- **Informs:** attention as a limiting factor when speech is degraded.
- **Does not validate:** the app's self-report scale as a measure of cortical
  resource allocation.

### Zekveld, Kramer, and Festen (2010) — pupillometry

Zekveld, A. A., Kramer, S. E., and Festen, J. M. “Pupil Response as an
Indication of Effortful Listening: The Influence of Sentence Intelligibility.”
*Ear and Hearing* 31(4), 480–490.
[DOI 10.1097/AUD.0b013e3181d4f251](https://doi.org/10.1097/AUD.0b013e3181d4f251)

- **Informs:** pupil dilation as a physiological correlate that can complement
  accuracy under difficult listening conditions.
- **Does not validate:** an app confidence/effort rating as pupillometry or an
  objective physiological measure.

## Auditory cortical organization

### Formisano et al. (2003) — human cortical tonotopy

Formisano, E., Kim, D.-S., Di Salle, F., van de Moortele, P.-F., Ugurbil, K.,
and Goebel, R. “Mirror-Symmetric Tonotopic Maps in Human Primary Auditory
Cortex.” *Neuron* 40(4), 859–869.
[DOI 10.1016/S0896-6273(03)00669-X](https://doi.org/10.1016/S0896-6273(03)00669-X)

- **Informs:** organized frequency preference in human auditory cortex.
- **Does not validate:** calling an eight-frequency behavioral curve a cortical
  map or locating the cause of a threshold deviation.

## Measurement standards and clinical context

These are professional guidelines rather than primary papers, but they define
important procedural and claim boundaries:

- American Speech-Language-Hearing Association. “Guidelines for Manual Pure-Tone
  Threshold Audiometry” (2005).
  <https://www.asha.org/policy/GL2005-00014/>
- American Speech-Language-Hearing Association. “Audiometric Symbols” (1990).
  <https://www.asha.org/policy/gl1990-00006/>

They inform familiarization, test frequencies, repeated 1 kHz measurement,
10-down/5-up search, symbol conventions, calibration, environment, and masking.
They do not turn an iPhone/headphone implementation into a clinical audiometer.

## Platform and safety sources

Primary platform documentation and public-health guidance are indexed in
[`REFERENCES.md`](REFERENCES.md). These include Apple's AVFoundation APIs, App
Review and privacy requirements, plus NIOSH hearing-safety material.

## Citation policy for a manuscript

Before submission:

1. Verify every citation against the version of record and export a reference
   library from a bibliographic manager.
2. Cite the original experiment for empirical claims; use reviews only for
   synthesis and historical context.
3. Distinguish preregistered hypotheses from exploratory analyses.
4. Describe SNR Lab QC as the test instrument, not as an already validated
   measure.
5. Include software version, commit identifier, iPhone and headset models,
   operating-system version, audio mode, and calibration status.
