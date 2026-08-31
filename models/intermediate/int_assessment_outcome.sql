select
    enrollment_id,
    score,
    pass_threshold,
    is_passed as is_credentialing_complete,
    graded_at
from {{ ref('stg_assessments') }}