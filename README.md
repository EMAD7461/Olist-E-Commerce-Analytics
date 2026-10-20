 Olist E-Commerce Analytics

 📌 Project Overview

This project focuses on analyzing Brazilian e-commerce data using SQL Server, Power Query, Excel, and Power BI.

The main objective is to clean, transform, validate, and analyze e-commerce data to extract meaningful business insights about orders, customers, sellers, products, payments, and shipping performance.

The project demonstrates practical skills in data preparation, relational database design, SQL querying, data modeling, and business intelligence reporting.

 🎯 Project Objectives

- Clean and prepare raw e-commerce datasets.
- Identify missing values, duplicates, inconsistent data, and data quality issues.
- Build and validate relationships between database tables.
- Analyze orders, payments, products, customers, sellers, and freight costs.
- Develop an interactive Power BI dashboard.
- Validate financial totals and investigate reconciliation differences.
- Present business insights through KPIs and visualizations.

 🛠️ Tools & Technologies

| Tool | Purpose |
|---|---|
| SQL Server | Database storage, SQL queries, validation, and relationship management |
| Power Query | Data cleaning and transformation |
| Excel | Data inspection and validation |
| Power BI | Data modeling, DAX measures, and interactive dashboards |
| Git & GitHub | Version control and project documentation |

 📂 Dataset

The project uses the Brazilian E-Commerce Public Dataset by Olist.

The dataset contains information about:

- Customers
- Orders
- Order items
- Payments
- Reviews
- Products
- Sellers
- Geolocation
- Product category translations

Original dataset: [Brazilian E-Commerce Public Dataset by Olist – Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

 🔄 Project Workflow

 1. Data Preparation

- Imported the source datasets.
- Reviewed column names and data types.
- Checked missing and blank values.
- Investigated duplicate records.
- Reviewed date, text, and financial fields.
- Standardized data where necessary.

 2. Database Development

- Organized data in SQL Server.
- Worked with staging and analytical tables.
- Investigated primary key and foreign key constraints.
- Checked duplicate keys and unmatched records.
- Reviewed relationships between related datasets.

 3. Data Validation

Financial validation included comparing order-item and freight totals with payment values.

Previously documented validation figures:

| Validation Metric | Amount |
|---|---:|
| Order item price + freight | R$ 15,843,553.24 |
| Payment value | R$ 16,008,872.12 |
| Difference requiring investigation | R$ 165,318.88 |

These figures represent previously documented checks and should be revalidated against the final dataset before being treated as final results. The difference is a reconciliation exception to investigate, not proof of missing revenue.

 4. Data Modeling

- Reviewed table relationships and key constraints.
- Investigated duplicate and unmatched key values.
- Prepared data for analytical reporting.
- Used a calendar table to support date-based analysis in Power BI.

 5. Power BI Dashboard

The reporting objective is to provide an interactive view of e-commerce performance through KPIs, charts, filters, and analytical pages.

Potential analysis areas include:

- Order and payment performance
- Product and category analysis
- Customer and seller analysis
- Freight and shipping costs
- Time-based trends
- Review and order status analysis

The final dashboard visuals and KPIs should be documented here once the report is finalized.

 📊 Key Skills Demonstrated

- Data Cleaning and Transformation
- SQL Server and Relational Database Concepts
- Data Quality Checks
- Primary Key and Foreign Key Validation
- Financial Reconciliation
- Power Query
- Power BI Data Modeling
- DAX and KPI Development
- Interactive Dashboard Design
- Technical Documentation
- GitHub Version Control

 🚀 How to Use This Project

1. Clone or download this repository.
2. Review the project documentation and SQL scripts.
3. Import the datasets into your local environment, if included.
4. Execute the SQL scripts in the documented order.
5. Open the Power BI report, if included, and configure its data source.
6. Refresh the data and review the dashboard results.

Note: Some files or datasets may not be included in the repository. Check the project folders and documentation before running the workflow.

 📁 Repository Structure

The repository may be organized as follows, depending on the files included:

```text
Olist-E-Commerce-Analytics/
├── data/
├── sql/
├── power-query/
├── power-bi/
├── excel/
├── reports/
├── images/
├── README.md
└── .gitignore
```

 👤 Author

Mohamed Emad

Data Analytics | SQL Server | Power BI | Excel | Power Query

