select
    customer_id,
    first_name || ' ' || last_name as full_name,
    email,
    created_at
from {{ ref('stg_customers') }}
