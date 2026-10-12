Welcome to your new dbt project!

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices

### Start
- Start env with 
```
python -m vevn dbt_study && cd dbt_study
```

- Install ibs
```
pip install dbt-duckdb pandas
```

Created seed data with

- seeds/raw_orders.csv
```
cat > seeds/raw_orders.csv << 'EOF'
id,customer_id,status,amount_cents,ordered_at
101,1,completed,2500,2024-03-01 10:15:00
102,1,completed,4200,2024-03-02 09:00:00
103,2,returned,1800,2024-03-02 14:30:00
104,3,completed,9900,2024-03-03 11:45:00
105,2,completed,3100,2024-03-04 16:20:00
106,4,pending,1500,2024-03-04 18:05:00
107,3,completed,2750,2024-03-05 08:10:00
EOF
```

- seeds/raw_customers.csv
```
cat > seeds/raw_customers.csv << 'EOF'
id,first_name,last_name,email,created_at
1,Ana,Silva,ana@example.com,2024-01-05
2,Bram,de Vries,bram@example.com,2024-01-12
3,Chloe,Jansen,chloe@example.com,2024-02-01
4,Dev,Patel,dev@example.com,2024-02-15
EOF
```

- Loaded up CSV data with
```
dbt seed --profiles-dir .
```

- Created the profiles.yml
```
cat > profiles.yml << 'EOF'
dbt_study:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: dbt_study.duckdb
      threads: 4
EOF
```

- Check that the duckdb landed csv
```
python -c "import duckdb; print(duckdb.connect('dbt_study.duckdb').sql('show tables').df())"
```

- Add some sources, as dbt uses it as references to external outputs (like external tables in Databricks, a pointer to a table managed outside the platform)
```
mkdir -p models/staging models/marts
cat > models/staging/_sources.yml << 'EOF'
version: 2

sources:
  - name: raw
    schema: main
    tables:
      - name: raw_customers
      - name: raw_orders
EOF
```

Staging here has a purpose of distinguishing what a source system provided, and all the transformations made inside DBT, so it has the start point

- Create the staging model, it's similar to the silver layer in medallion architecture
```
cat > models/staging/stg_customers.sql << 'EOF'
select
    id as customer_id,
    first_name,
    last_name,
    lower(email) as email,
    cast(created_at as date) as created_at
from {{ source('raw', 'raw_customers') }}
EOF

cat > models/staging/stg_orders.sql << 'EOF'
select
    id as order_id,
    customer_id,
    status,
    amount_cents / 100.0 as amount,
    cast(ordered_at as timestamp) as ordered_at
from {{ source('raw', 'raw_orders') }}
EOF
```

Next come ***marts***, which are the analytics layers, where business logic live, using the staging data to be able to define metrics, dimensions and facts.

All references in DBT are made through the models, in this sense, its the ***{{ ref }}*** macro in Jinja templates, so it constructs the DAG based on the references (wheter materialized or not) on top of them.

Materialization configs constructs what will be physically stored or not, for instance, views / stagings will have no storage and marts as tables will, so it can be consumed in BI tooling for example.

- Creating the dims and facts
```
cat > models/marts/dim_customers.sql << 'EOF'
select
    customer_id,
    first_name || ' ' || last_name as full_name,
    email,
    created_at
from {{ ref('stg_customers') }}
EOF

cat > models/marts/fct_customer_orders.sql << 'EOF'
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
EOF
```

In ***dbt_study.yml*** the materialization for each step is determined, a ***+*** will define a standard for each folder.

```
dbt run
```

this will do 5 things, parse the project, construct the DAG, compile the Jinja templating to SQL, wrap models into DDLs according to the materialization and execute against the compute.
The steps can be seen against the
```
/target
```
folder, where DBT produces the output files