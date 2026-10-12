with orders as (
    select * from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
)

select
    c.customer_id,
    c.full_name,
    count(o.order_id) as total_orders,
    sum(case when o.status = 'completed' then o.amount else 0 end) as completed_revenue,
    min(o.ordered_at) as first_order_at
from customers c
left join orders o using (customer_id)
group by 1, 2
