# Cost Report — MSK + Aurora -> Redshift (estimate)

Summary
- Approximate monthly total: **$1,216.14 USD** (on‑demand, US‑East‑1 assumptions)

Breakdown (high level)
- MSK cluster (2 × kafka.m5.large + 1000 GB per broker): $300.16/mo
- Aurora writer (db.r5.large + 100 GB): $101.98/mo
- Redshift (1 × ra3.xlplus): $803.00/mo
- S3 / CloudWatch / misc: ~$11.00/mo

Assumptions & notes
- Hourly basis uses 730 hours/month.
- Unit prices are approximate on‑demand rates used for quick estimation:
  - `kafka.m5.large` compute: $0.096/hr
  - EBS-like storage (for MSK brokers): $0.08/GB‑mo
  - `db.r5.large`: $0.126/hr
  - Aurora storage: $0.10/GB‑mo
  - `ra3.xlplus`: $1.10/hr (node cost only)
- Does NOT include:
  - Data transfer costs (can be large for cross‑AZ / cross‑region traffic)
  - Backups/snapshots beyond minimal assumptions
  - Reserved instance or savings plan discounts

How this was generated
- Derived from Terraform state resource counts and attributes (broker count, instance types, storage sizes). This is a quick estimate to guide cost decisions; use AWS Cost Explorer or the AWS Pricing Calculator for precise budgeting.

Next steps
- I can: generate a CSV with exact per‑resource line items extracted from the current Terraform state, or build an AWS Pricing Calculator template for import. Which do you want? (CSV / Pricing Calculator)
