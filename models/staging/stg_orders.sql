select
    id as order_id,
    customer_id,
    status,
    amount_cents / 100.0 as amount,
    cast(ordered_at as timestamp) as ordered_at
from {{ source('raw', 'raw_orders') }}
