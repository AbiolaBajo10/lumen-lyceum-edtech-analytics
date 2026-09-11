# Lumen Lyceum: EdTech Learning Analytics

**Reconciling completion: 45.0% (Curriculum) vs. 29.9% (Credentialing)**

## Background

Lumen Lyceum is an online learning platform that sells self-paced courses. A learner enrols in a course, works through its lessons, and sits a final exam at the end. The unit of analysis throughout this project is the enrolment (one student's one attempt at one course), not the student, since the same person can enrol in multiple courses or re-enrol in the same one.

Two teams at Lumen Lyceum each run their own dashboard to track how well learners are finishing their courses. The Curriculum team measures completion by lesson progress: did the learner get through all the material. The Credentialing team measures it by exam outcome: did the learner pass the final assessment. The two dashboards have never agreed with each other, and until now nobody had built anything that explained why.

## Executive Summary

The Curriculum team reports 45.0% course completion. The Credentialing team reports 29.9%. Both numbers are correct, they simply measure different things, and neither dashboard was built to explain the other.

This project delivers a single learning-analytics mart (`fct_enrollments`) that both teams can query, carrying both completion definitions side by side rather than collapsing them into one figure. A dedicated reconciliation model walks the 15-point gap between the two numbers line by line, attributing it to three distinct populations rather than leaving it unexplained. Along the way, six data-quality issues were identified and fixed, including corrupted source timestamps traced to a bug in the upstream data generator and resolved at the source. The pipeline is fully tested (23 passing tests), monitored with severity-tiered alerting, and designed for daily orchestration.

## Stack
Snowflake, dbt, (Airflow/Dagster/Prefect, design only, see below)

## Project structure
```
models/
├── staging/        stg_students, stg_courses, stg_lessons, stg_assessments
├── intermediate/   int_lesson_completion, int_assessment_outcome
└── marts/          fct_enrollments, mart_engagement_metrics, mart_completion_reconciliation
```

## 1. The mart

`fct_enrollments` is the single fact table both teams query, at the enrolment grain.

Rather than picking a winner, it carries both completion definitions as explicit flags:
- `is_curriculum_complete`: 100% of the course's lessons completed (Curriculum's definition)
- `is_credentialing_complete`: the final exam passed (Credentialing's definition)
- `completion_reconciled`: a bucketed comparison of the two, used in the bridge below

## 2. Student-engagement metrics

| Metric | Definition | Value |
|---|---|---|
| Completion rate (lessons-based) | % of enrolments where all lessons were completed | 45.0% |
| Completion rate (assessment-based) | % of enrolments where the final exam was passed | 29.9% |
| Avg. lessons completed | Mean distinct lessons completed per enrolment | 6.72 |
| Avg. % lessons completed | Mean of (lessons completed ÷ course lesson count) | 67.0% |
| Assessment pass rate | Of enrolments that attempted the exam, % that passed | 70.8% |
| Active learners (28-day window) | Enrolments active within 28 days of enrolling | 31.4% (15,693 of 50,000) |
| Median time-to-complete | Median days enrolment to last activity, lesson-complete enrolments only | 45 days |

## 3. Reconciliation, bridging 45.0% and 29.9%

`mart_completion_reconciliation` buckets every enrolment into one of four mutually exclusive outcomes:

| Bucket | Enrolments | % of total |
|---|---|---|
| Incomplete on both definitions | 25,179 | 50.4% |
| Finished lessons and passed the exam | 12,612 | 25.2% |
| Finished lessons, never sat or failed the exam | 9,890 | 19.8% |
| Tested out, passed without finishing every lesson | 2,319 | 4.6% |

**The bridge:** 45.0% finished every lesson (25.2% + 19.8%). Of those, 25.2 points also passed the exam. The remaining 19.8 points finished the lessons but never sat, or failed, the exam, the largest single driver of the gap. A further 4.6% passed without finishing every lesson ("tested out"), which is why the assessment-based rate isn't a clean subset of the lessons-based one. Net: 25.2% + 4.6% is approximately 29.9%.

**Where the platform's own status field disagrees:**
- 162 enrolments are marked `completed` by the platform's overnight job but never passed the exam.
- 2,068 "tested out" enrolments are not marked `completed`, despite passing. The status job appears to key off lesson completion, missing this population entirely.
- 30 enrolments disagree with both definitions at once.

## 4. Data-quality findings

| Issue | Fixed here? | Fix / recommendation |
|---|---|---|
| Duplicate lesson-completion logs (device-switch resume) | Fixed | Deduplicated in staging, keep latest `completed_at` per enrolment + lesson |
| Ungraded / in-flight assessment attempts | Fixed | Filtered to `attempt_status = 'graded'` only; not treated as failed |
| Dropped session-end timestamps (`completed_at` null) | Handled | Left null, treated as incomplete, not imputed |
| Stale platform status field | Surfaced | Never trusted as ground truth, compared against both definitions instead |
| Person-vs-enrolment grain trap | Fixed | Modeled at enrolment grain throughout; `student_id` never used as a dedup key |
| Corrupted raw timestamps (`enrolled_at`/`last_active_at`) | Fixed at source | See below |

### Resolved: corrupted raw timestamps

`enrolled_at` and `last_active_at` initially loaded into Snowflake as corrupted values (e.g. year -1,688,798,502) via the data generator's `write_pandas` upload step. This was traced down to the upload itself: the generator's own Python date logic (`_random_datetimes`) produced correct values, and the corruption happened specifically during the write to Snowflake, independent of any dbt modeling. The generator was corrected and the raw tables reloaded; `enrolled_at` and `last_active_at` now show valid 2024-2025 dates, and `active_within_28_days`, `days_active_span`, and `median_days_to_complete` are confirmed correct along with every other metric in this project.

## 5. Pipeline monitoring

| Severity | Applied to | On failure |
|---|---|---|
| `error` | `unique`/`not_null` on `enrollment_id`, `course_id` relationship, `pct_lessons_completed` range | Build fails, downstream models skipped, engineer paged, last-good data served |
| `warn` | `completion_reconciled` accepted values | Logged in `run_results.json`, build continues, reviewed periodically |

Source freshness checked before staging runs: warn after 30h since last load, error after 48h.

## 6. Daily orchestration (design)

A running DAG is a stretch goal, this is the design and reasoning.

```
check source freshness → staging models → intermediate models → mart models → tests → docs
```

- **Schedule:** daily around 3 AM, after the platform's overnight export; the freshness check is the real gate, not the clock.
- **Alerting:** freshness/test failures alert the data team; a run error gets one retry (5 min) before paging.
- **Idempotency:** every `dbt run` is safe to re-run.

## 7. Key assumptions

- Unit of analysis is the enrolment, not the learner (per the engagement brief).
- "Curriculum complete" means 100% of lessons, not a partial threshold.
- 28-day active-learner window measured from `enrolled_at`, not rolling from today.
- Latest graded assessment attempt represents the enrolment's outcome.
- The platform's status field is treated as untrusted, never as ground truth.

Full rationale for each is in [`04-assumptions-log.md`](./04-assumptions-log.md).

## Recommendation

**Report both completion rates, side by side, permanently. Do not collapse them into one number.** They measure genuinely different things, and a single blended figure would hide exactly the distinction both teams need. Practically:

- Ship `fct_enrollments` and `mart_completion_reconciliation` as the shared source of truth both teams query directly, rather than each team maintaining its own disconnected calculation.
- Use the reconciliation bucket breakdown as the standing reference whenever the two numbers are questioned. It already answers "why don't these match" without further ad hoc analysis.
- Fix the platform's overnight status job separately from this pipeline. It disagrees with both modeled definitions (most notably missing the entire "tested out" population) and is actively misleading as an unlabeled third version of "complete."
- The source timestamp bug (see [Resolved: corrupted raw timestamps](#resolved-corrupted-raw-timestamps)) has been fixed; the active-learner and time-to-complete metrics above are confirmed reliable.

## Conclusion

The two teams' numbers were never actually in conflict, they were answering different questions without saying so. This project replaces that ambiguity with one mart, two explicit definitions, and a model that shows exactly how 45.0% and 29.9% relate to each other. What's left is largely operational: decide whether to build out the orchestration DAG beyond the current design, and get the platform's status job aligned with what the underlying event data actually shows.

## Submission set

- [`02-architecture-diagram.svg`](./02-architecture-diagram.svg)
- [`03-source-to-target-map.md`](./03-source-to-target-map.md)
- [`04-assumptions-log.md`](./04-assumptions-log.md)
- [`05-capstone-deck.pptx`](./05-capstone-deck.pptx)
