with base as (
    select * from {{ ref('fct_enrollments') }}
),

bucketed as (
    select
        enrollment_id,
        is_curriculum_complete,
        is_credentialing_complete,
        source_system_status,
        case
            when is_curriculum_complete and is_credentialing_complete
                then 'finished_and_passed'
            when is_curriculum_complete and not coalesce(is_credentialing_complete, false)
                then 'finished_lessons_never_sat_exam_or_failed'
            when not coalesce(is_curriculum_complete, false) and is_credentialing_complete
                then 'tested_out_without_finishing_lessons'
            when not coalesce(is_curriculum_complete, false) and not coalesce(is_credentialing_complete, false)
                then 'incomplete_both'
        end as reconciliation_bucket,
        (source_system_status = 'completed' and not is_curriculum_complete) as platform_says_complete_but_lessons_say_no,
        (source_system_status = 'completed' and not coalesce(is_credentialing_complete, false)) as platform_says_complete_but_exam_says_no
    from base
)

select
    reconciliation_bucket,
    count(*) as enrollment_count,
    count(*) / sum(count(*)) over () as pct_of_total,
    sum(case when platform_says_complete_but_lessons_say_no then 1 else 0 end) as platform_status_disagrees_lessons,
    sum(case when platform_says_complete_but_exam_says_no then 1 else 0 end) as platform_status_disagrees_exam
from bucketed
group by 1
order by enrollment_count desc