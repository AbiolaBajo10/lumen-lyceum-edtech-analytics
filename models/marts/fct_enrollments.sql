with students as (
    select * from {{ ref('stg_students') }}
),

lesson_completion as (
    select * from {{ ref('int_lesson_completion') }}
),

assessment_outcome as (
    select * from {{ ref('int_assessment_outcome') }}
)

select
    s.enrollment_id,
    s.student_id,
    s.course_id,
    s.plan,
    s.locale,
    s.enrollment_status as source_system_status,
    s.enrolled_at,
    s.last_active_at,

    -- engagement window
    datediff('day', s.enrolled_at, s.last_active_at) as days_active_span,
    s.last_active_at <= dateadd('day', 28, s.enrolled_at) as active_within_28_days,

    -- curriculum team definition
    lc.lessons_completed,
    lc.pct_lessons_completed,
    lc.is_curriculum_complete,

    -- credentialing team definition
    ao.score as final_exam_score,
    ao.is_credentialing_complete,

    -- reconciled view: flag where the two definitions disagree
    case
        when lc.is_curriculum_complete and not coalesce(ao.is_credentialing_complete, false)
            then 'finished_lessons_no_pass'
        when not coalesce(lc.is_curriculum_complete, false) and ao.is_credentialing_complete
            then 'passed_without_finishing_lessons'
        when lc.is_curriculum_complete and ao.is_credentialing_complete
            then 'complete_both'
        else 'incomplete'
    end as completion_reconciled

from students s
left join lesson_completion lc on s.enrollment_id = lc.enrollment_id
left join assessment_outcome ao on s.enrollment_id = ao.enrollment_id