with base as (
    select * from {{ ref('fct_enrollments') }}
)

select
    avg(case when is_curriculum_complete then 1 else 0 end)      as completion_rate_lessons_based,
    avg(case when is_credentialing_complete then 1 else 0 end)   as completion_rate_assessment_based,
    count(case when active_within_28_days then 1 end)            as active_learners_28day,
    count(*)                                                      as total_enrollments,
    avg(lessons_completed)                                        as avg_lessons_completed,
    avg(pct_lessons_completed)                                    as avg_pct_lessons_completed,
    avg(case when final_exam_score is not null
             then case when is_credentialing_complete then 1 else 0 end end) as assessment_pass_rate,
    median(case when is_curriculum_complete
                then datediff('day', enrolled_at, last_active_at) end) as median_days_to_complete
from base