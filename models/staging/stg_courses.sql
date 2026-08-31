select
    course_id,
    course_title,
    category,
    lesson_count,
    pass_threshold,
    is_active,
    created_at
from {{ source('learnsphere_raw', 'raw_courses') }}