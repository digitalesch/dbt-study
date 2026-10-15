## Start

It'll start with macros, seeds, snapshots and packages.

- Macros are defined to remove repeated code, since they can be defined once and reused throughout the models.
- Seeds are small reference data to be added in the lake
- Snapshots are the incremental part where every version / run are kept, not just the current state

### First macro
Macros are defined as Jinja templates and are under the ***/macros*** folder, taking arguments and returning text, which dbt changes when it compiles the SQLs, so the compute never sees the macro, just the compiled SQLs.

### Added the acceptance test to be able to accept refunds in the seed data

![Refunds](0005_refund_tests_acceptance.png)

For the macro the distinction is
- ***{{ ... }}*** outputs a value.
- ***{% ... %}*** runs a statement (loops, ifs, macro definitions).
- ***{# ... #}*** is a comment.

### Macro creation
```
cat > macros/cents_to_currency.sql << 'EOF'
{% macro cents_to_currency(column_name, precision=2) %}
    round({{ column_name }} / 100.0, {{ precision }})
{% endmacro %}
EOF

cat > models/staging/stg_orders.sql << 'EOF'
select
    id as order_id,
    customer_id,
    status,
    {{ cents_to_currency('amount_cents') }} as amount,
    cast(ordered_at as timestamp) as ordered_at,
    cast(updated_at as timestamp) as updated_at
from {{ source('raw', 'raw_orders') }}
EOF

dbt compile --select stg_orders --profiles-dir .
cat target/compiled/dbt_study/models/staging/stg_orders.sql
```

after running the compile
```
dbt compile --select stg_orders --profiles-dir .
```

the target file
```
cat target/compiled/dbt_study/models/staging/stg_orders.sql
```

will show the macro expansion from Jinja
```
{% macro cents_to_currency(column_name, precision=2) %}
    round({{ column_name }} / 100.0, {{ precision }})
{% endmacro %}
```

to
```
round(amount_cents / 100.0, 2)
```

Macros can contain loops inside it with 
```
{{ % for % }}
```

example
```
{% set statuses = var('order_statuses', ['completed', 'returned', 'pending']) %}

select
    customer_id
    {% for s in statuses %}
    , sum(case when status = '{{ s }}' then 1 else 0 end) as {{ s }}_orders
    {% endfor %}
from {{ ref('fct_orders') }}
group by 1
EOF

```

getting compiled to

![Macro compilation](0006_compiled_macro.png)

## Packages
Similar to a ***requirements.txt*** fro python modules, the dbt package can be have shared macros, tests and models, packages in the ***packages.yaml*** file.

This lets cross-database portability, since the package can 

example 
```
cat > packages.yml << 'EOF'
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.3.0", "<2.0.0"]
EOF
dbt deps --profiles-dir .
```

And the package in this case provides a surrogate_key function, which can be used here

```
cat > models/marts/dim_customers.sql << 'EOF'
select
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }} as customer_key,
    customer_id,
    first_name || ' ' || last_name as full_name,
    email,
    created_at
from {{ ref('stg_customers') }}
EOF

cat > models/marts/_marts.yml << 'EOF'
version: 2

models:
  - name: fct_orders
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: amount
        data_tests:
          - dbt_utils.accepted_range:
              min_value: 0

  - name: dim_customers
    columns:
      - name: customer_key
        data_tests:
          - unique
          - not_null
EOF

rm tests/assert_amount_non_negative.sql
dbt build --profiles-dir . --select dim_customers fct_orders
```

Added seed for process status mapping, and updated the fact table that uses it that was previously hardcoded
```
cat > seeds/order_status_map.csv << 'EOF'
status,revenue_flag
completed,1
returned,0
pending,0
EOF

cat > models/marts/fct_customer_orders.sql << 'EOF'
with orders as (
    select * from {{ ref('stg_orders') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

status_map as (
    select * from {{ ref('order_status_map') }}
)

select
    c.customer_id,
    c.full_name,
    count(o.order_id) as total_orders,
    sum(case when m.revenue_flag = 1 then o.amount else 0 end) as completed_revenue,
    min(o.ordered_at) as first_order_at
from customers c
left join orders o using (customer_id)
left join status_map m on o.status = m.status
group by 1, 2
EOF
```

and ran it with 
```
dbt seed --profiles-dir .
dbt run --select fct_customer_orders --profiles-dir .
```

## Snapshots (SCD Type 2)
It records every change given the unique id and checks for changes in specific columns, this is done in source tables, not in models since the snapshot can't be rebuilt with the ***--full-refresh***

Example:
```
cat > snapshots/snap_customers.sql << 'EOF'
{% snapshot snap_customers %}

{{ config(
    target_schema='snapshots',
    unique_key='id',
    strategy='check',
    check_cols=['first_name', 'last_name', 'email']
) }}

select * from {{ source('raw', 'raw_customers') }}

{% endsnapshot %}
EOF

dbt snapshot --profiles-dir .
```

![Snapshot creation](0007_snapshot_creation.png)

Changing a row in the seed
```
cat > seeds/raw_customers.csv << 'EOF'
id,first_name,last_name,email,created_at
1,Ana,Silva,ana.silva@newmail.com,2024-01-05
2,Bram,de Vries,bram@example.com,2024-01-12
3,Chloe,Jansen,chloe@example.com,2024-02-01
4,Dev,Patel,dev@example.com,2024-02-15
5,Eva,Mulder,eva@example.com,2024-03-10
EOF

dbt seed --profiles-dir .
dbt snapshot --profiles-dir .
python -c "import duckdb; print(duckdb.connect('dbt_study.duckdb').sql('select id, email, dbt_valid_from, dbt_valid_to from snapshots.snap_customers order by id, dbt_valid_from').df())"
```

Since "Ana" now changed data on the email, it gets a new row, and validity with the timestamps
![Seed change and snapshot](0008_snapshot_seed_change.png)

Mode of a convention naming here

| Prefix |	Meaning |	Folder |
| ------ | -------- | -------- |
| stg_	| Staging, 1:1 with a source table |	models/staging/ |
| int_	| Intermediate building blocks (joins, reusable logic)	| models/intermediate/ |
|fct_ |	Fact (events, transactions) |	models/marts/ |
|dim_ |	Dimension (entities)	| models/marts/ |
|snap_ |	Snapshot |	snapshots/ |