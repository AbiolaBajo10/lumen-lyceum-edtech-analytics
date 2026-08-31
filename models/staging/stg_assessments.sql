select
    assessment_attempt_id,
    enrollment_id,
    student_id,
    course_id,
    assessment_type,
    score,
    pass_threshold,
    is_passed,
    attempt_status,
    submitted_at,
    graded_at
from {{ source('learnsphere_raw', 'raw_assessments') }}
where attempt_status = 'graded'
qualify row_number() over (
    partition by enrollment_id
    order by graded_at desc
) = 1