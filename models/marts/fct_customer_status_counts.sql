{% set statuses = var('order_statuses', ['completed', 'returned', 'pending']) %}

select
    customer_id
    {% for s in statuses %}
    , sum(case when status = '{{ s }}' then 1 else 0 end) as {{ s }}_orders
    {% endfor %}
from {{ ref('fct_orders') }}
group by 1
