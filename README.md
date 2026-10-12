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

- Loaded up with 
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
      path: shop.duckdb
      threads: 4
EOF
```

- Check that the duckdb landed csv
```
python -c "import duckdb; print(duckdb.connect('shop.duckdb').sql('show tables').df())"
```