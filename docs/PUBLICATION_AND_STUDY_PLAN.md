# Publication and study plan

This document turns the engineering prototype into a staged research program.
It is not an ethics approval, clinical protocol, statistical guarantee, or claim
that the current scores are validated.

## Candidate contribution

The defensible research contribution is the integrated, local-first measurement
workflow and the relationships among its behavioral domains:

1. bilateral uncalibrated relative tone detection;
2. bilingual speech recognition across controlled digital SNRs and maskers;
3. behavioral context, restoration, misleading-prediction, and adaptation
   contrasts; and
4. transparent quality data and individualized left/right experimental EQ.

The individual paradigms have substantial prior literature. Novelty must
therefore be claimed at the level of the integrated protocol, implementation,
dataset, analysis, or validated finding—not as invention of audiometry, SPIN,
phonemic restoration, predictive processing, or equalization. Patent novelty and
academic novelty are separate questions that require their own searches.

## Proposed paper sequence

### Paper 1 — engineering and measurement characterization

**Question:** Is the iPhone/headset implementation technically stable enough to
support a behavioral study?

Report digital stimulus verification, acoustic measurements by headset model and
condition, left/right channel integrity, route interruption handling, timing,
level repeatability, clipping/headroom, and software tests. This paper should not
claim hearing validity.

### Paper 2 — behavioral feasibility and repeatability

**Question:** Can listeners complete the end-to-end protocol, and how repeatable
are its within-device relative measures?

Primary outcomes could include completion rate, test duration, catch-trial false
positive rate, repeated-1-kHz difference, test–retest agreement, SNR50
repeatability, and predictive-module trial reliability.

### Paper 3 — preregistered construct/criterion validation

**Question:** How do app measures relate to calibrated audiometry and validated
speech tests when collected by qualified researchers under controlled
conditions?

This requires reference instruments, blinded or counterbalanced administration,
predefined acceptance criteria, and an analysis that does not mistake
correlation for interchangeability.

## Pilot protocol

### Population

- Adults able to give informed consent and complete English or Spanish materials.
- Record age, language history, self-reported hearing history, tinnitus, relevant
  neurological history, and accessibility needs.
- Define inclusion/exclusion criteria before recruitment. Do not exclude data
  after seeing outcomes except under preregistered quality rules.

Children, clinical populations, and neurological claims require a separate
risk/ethics assessment and age-appropriate validated materials.

### Equipment and environment

- Fix iPhone model, iOS version, app version/commit, headset model and firmware
  within a study cell.
- Use a documented noise-control mode and fixed system volume.
- Verify left/right routing and fit at every session.
- Characterize the room and record calibrated ambient SPL when making laboratory
  claims. The app's microphone estimate remains a quality indicator, not a
  substitute for a sound-level meter.
- Measure headphone output on appropriate laboratory equipment before relating
  results to acoustic level.

### Session structure

1. Consent, eligibility, language, device, environment, and setup record.
2. Standardized instructions and practice.
3. Bilateral tone module, with ear order randomized or counterbalanced.
4. Rest period.
5. Speech-in-noise module, with voice/masker/list order balanced.
6. Predictive-listening module, with condition order controlled by the frozen
   protocol.
7. Post-test effort, comfort, and usability questionnaire.
8. Repeat session after a preregistered interval for reliability.

The study should decide in advance whether the “Complete Listening Profile” app
order is the construct being studied or whether order is counterbalanced to
estimate order effects.

## Outcomes

### Primary feasibility outcomes

- Proportion completing each module and the full protocol.
- Duration and number of trials.
- Adverse events, discomfort, and stops.
- Data completeness and route/setup failures.

### Reliability outcomes

- Repeated 1 kHz within-session difference by ear.
- Test–retest difference and agreement for each relative frequency threshold.
- Test–retest difference for SNR50 and, only where estimated with adequate data,
  SNR80/SNR90.
- Reliability of context, restoration, intrusion, and adaptation contrasts.

### Construct outcomes

- Association between relative frequency thresholds and calibrated reference
  thresholds, analyzed per ear and frequency.
- Association between app speech-in-noise outcomes and a validated language-
  appropriate reference task.
- Prespecified effects of high versus low context, noise-filled versus silent
  gaps, and early versus late stable-distortion trials.

No threshold of “normal,” “impaired,” or “brain dysfunction” should be introduced
without external validation, normative sampling, and appropriate clinical and
regulatory review.

## Statistical analysis principles

- Preserve trial-level data; avoid analysis based only on exported summaries.
- Model binary word/trial outcomes with an appropriate generalized mixed-effects
  model when the design supports it, including listener and item variation.
- Treat ear and frequency as repeated factors rather than independent samples.
- Report effect sizes and uncertainty, not only p-values.
- Use agreement analysis for interchangeability questions; correlation alone is
  insufficient.
- Predefine missing-data, incomplete-staircase, false-positive, and route-failure
  handling.
- Correct or hierarchically control multiple comparisons across frequencies,
  ears, maskers, languages, and predictive contrasts.
- Check language/item measurement equivalence before pooling English and Spanish.
- Keep exploratory model selection and confirmatory hypothesis tests separate.

The repository intentionally provides no invented sample size. Run a small
technical/pilot phase to estimate variance and completion, then calculate the
confirmatory sample size from the smallest scientifically important effect,
desired power, design, multiplicity plan, and expected attrition. Record the
calculation in the preregistration.

## Bias control

- Randomize or counterbalance ear, list, voice, masker, and module order where
  compatible with the research question.
- Freeze sentence lists and stimulus-generation version before confirmatory data
  collection.
- Separate participants by session and do not reveal trial correctness during
  predictive blocks.
- Blind reference-test assessors to app results when feasible.
- Analyze all preregistered outcomes and disclose deviations.
- Track practice, prior app exposure, and repeated sentences.

## Reproducibility package

A publication release should include, subject to consent and ethics approval:

- tagged source code and immutable commit identifier;
- exact build settings and dependency/toolchain versions;
- versioned stimulus metadata and randomization seeds or plans;
- data dictionary and machine-readable schema;
- de-identified trial-level data or a justified controlled-access process;
- analysis code, environment lockfile, and a one-command reproduction guide;
- synthetic example data for public testing;
- CONSORT-style flow diagram where applicable and a deviations log;
- acoustic calibration report for every study device cell;
- preregistration and ethics identifiers.

Do not publish names, free text, device identifiers, health information, or raw
research data without an approved consent and de-identification process.

## Ethics, safety, and regulatory boundary

- Obtain review by the relevant institutional ethics body before research with
  human participants; consent must describe audio exposure, data, risks,
  withdrawal, and compensation.
- Establish calibrated maximum acoustic exposure and stopping rules before a
  laboratory study. Digital dBFS limits alone do not establish ear-level safety.
- Provide referral language for concerns without interpreting the app as a
  diagnosis.
- Treat a future diagnostic, treatment, or hearing-aid claim as a separate
  medical-device/regulatory workstream.
- Register conflicts of interest, funding, author contributions, and software
  ownership.

## Suggested manuscript structure

1. **Introduction:** unmet measurement question, prior work, explicit gap, and
   hypotheses.
2. **Methods:** participants, ethics, apparatus, calibration, stimuli, algorithms,
   randomization, outcomes, exclusions, and analysis.
3. **Results:** recruitment flow, quality, primary outcomes, uncertainty,
   sensitivity analyses, and harms.
4. **Discussion:** interpretation, comparison with prior work, limitations,
   generalizability, and non-diagnostic boundary.
5. **Open practices:** registration, data/code access, version and commit.

## Immediate pre-study gates

- [ ] Complete acoustic characterization on every supported study headset.
- [ ] Validate stimulus timing and channel separation externally.
- [ ] Freeze and linguistically review English and Spanish sentence banks.
- [ ] Add research export with explicit consent and de-identification controls.
- [ ] Write the data dictionary and statistical analysis plan.
- [ ] Complete usability/accessibility testing.
- [ ] Obtain ethics approval and preregister the pilot.
- [ ] Run a monitored pilot before any confirmatory claim.

The evidence base motivating these modules is summarized in
[`PAPER_BIBLIOGRAPHY.md`](PAPER_BIBLIOGRAPHY.md), and the app's measurement
limits are detailed in [`VALIDATION.md`](VALIDATION.md).
