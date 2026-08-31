# Source-to-Target Map — Lumen Lyceum EdTech Analytics

## `stg_students` ← `RAW.RAW_STUDENTS`
| Target column | Source column | Transformation |
|---|---|---|
| enrollment_id | enrollment_id | direct |
| student_id | student_id | direct |
| course_id | course_id | direct |
| plan | plan | direct |
| locale | locale | direct |
| enrollment_status | enrollment_status | direct |
| enrolled_at | enrolled_at | direct |
| last_active_at | last_active_at | direct |

## `stg_courses` ← `RAW.RAW_COURSES`
| Target column | Source column | Transformation |
|---|---|---|
| course_id | course_id | direct |
| course_title | course_title | direct |
| category | category | direct |
| lesson_count | lesson_count | direct |
| pass_threshold | pass_threshold | direct |
| is_active | is_active | direct |
| created_at | created_at | direct |

## `stg_lessons` ← `RAW.RAW_LESSONS`
| Target column | Source column | Transformation |
|---|---|---|
| lesson_event_id | lesson_event_id | direct |
| enrollment_id | enrollment_id | direct |
| lesson_number | lesson_number | direct |
| lesson_status | lesson_status | direct |
| completed_at | completed_at | direct, but row deduplicated: `qualify row_number() over (partition by enrollment_id, lesson_number, lesson_status order by completed_at desc nulls last) = 1` — keeps latest event when a device switch produced duplicate completions |

## `stg_assessments` ← `RAW.RAW_ASSESSMENTS`
| Target column | Source column | Transformation |
|---|---|---|
| assessment_attempt_id | assessment_attempt_id | direct |
| enrollment_id | enrollment_id | direct |
| score | score | direct |
| is_passed | is_passed | direct, renamed downstream to `is_credentialing_complete` |
| attempt_status | attempt_status | filtered to `= 'graded'` only |
| graded_at | graded_at | direct; used to keep only the latest graded attempt per enrolment via `qualify row_number()... order by graded_at desc = 1` |

## `int_lesson_completion` ← `stg_lessons` + `stg_courses`
| Target column | Source | Transformation |
|---|---|---|
| enrollment_id | stg_lessons.enrollment_id | direct, grouping key |
| lessons_completed | stg_lessons.lesson_number, lesson_status | `count(distinct lesson_number)` where `lesson_status = 'completed'` |
| lesson_count | stg_courses.lesson_count | joined on course_id |
| pct_lessons_completed | (computed) | `lessons_completed / lesson_count` (safe-divide) |
| is_curriculum_complete | (computed) | `pct_lessons_completed >= 1.0` |

## `int_assessment_outcome` ← `stg_assessments`
| Target column | Source column | Transformation |
|---|---|---|
| enrollment_id | enrollment_id | direct |
| final exam score | score | direct |
| is_credentialing_complete | is_passed | renamed |

## `fct_enrollments` ← `stg_students` + `int_lesson_completion` + `int_assessment_outcome`
| Target column | Source | Transformation |
|---|---|---|
| enrollment_id | stg_students.enrollment_id | primary key |
| student_id, course_id, plan, locale | stg_students | direct |
| source_system_status | stg_students.enrollment_status | renamed |
| enrolled_at, last_active_at | stg_students | direct |
| days_active_span | (computed) | `datediff('day', enrolled_at, last_active_at)` |
| active_within_28_days | (computed) | `last_active_at <= dateadd('day', 28, enrolled_at)` |
| pct_lessons_completed, is_curriculum_complete | int_lesson_completion | joined on enrollment_id |
| final_exam_score, is_credentialing_complete | int_assessment_outcome | joined on enrollment_id |
| completion_reconciled | (computed) | case logic comparing `is_curriculum_complete` and `is_credentialing_complete` — see build guide |

## `mart_engagement_metrics` ← `fct_enrollments`
| Target column | Source | Transformation |
|---|---|---|
| completion_rate_lessons_based | is_curriculum_complete | `avg(case when ... then 1 else 0 end)` |
| completion_rate_assessment_based | is_credentialing_complete | `avg(case when ... then 1 else 0 end)` |
| active_learners_28day | active_within_28_days | `count(case when ... then 1 end)` |
| avg_lessons_completed | lessons_completed | `avg()` |
| assessment_pass_rate | final_exam_score, is_credentialing_complete | `avg()` conditioned on attempt existing |
| median_days_to_complete | enrolled_at, last_active_at, is_curriculum_complete | `median(datediff(...))` conditioned on lesson-complete |

## `mart_completion_reconciliation` ← `fct_enrollments`
| Target column | Source | Transformation |
|---|---|---|
| reconciliation_bucket | is_curriculum_complete, is_credentialing_complete | case logic, 4 mutually exclusive buckets |
| enrollment_count | enrollment_id | `count(*)` per bucket |
| pct_of_total | enrollment_count | `count(*) / sum(count(*)) over ()` |
| platform_status_disagrees_lessons | source_system_status, is_curriculum_complete | `sum(case when status='completed' and not curriculum_complete then 1 else 0 end)` |
| platform_status_disagrees_exam | source_system_status, is_credentialing_complete | `sum(case when status='completed' and not credentialing_complete then 1 else 0 end)` |
