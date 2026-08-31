with lesson_progress as (
    select
        l.enrollment_id,
        count(distinct case when l.lesson_status = 'completed' then l.lesson_number end) as lessons_completed,
        c.lesson_count
    from {{ ref('stg_lessons') }} l
    left join {{ ref('stg_courses') }} c on l.course_id = c.course_id
    group by 1, 3
)
select
    enrollment_id,
    lessons_completed,
    lesson_count,
    div0(lessons_completed, lesson_count) as pct_lessons_completed,
    pct_lessons_completed >= 1.0 as is_curriculum_complete
from lesson_progress