select
    lesson_event_id,
    enrollment_id,
    student_id,
    course_id,
    lesson_number,
    lesson_type,
    lesson_status,
    device,
    duration_minutes,
    started_at,
    completed_at
from {{ source('learnsphere_raw', 'raw_lessons') }}
qualify row_number() over (
    partition by enrollment_id, lesson_number, lesson_status
    order by completed_at desc nulls last
) = 1