# Cloud-Based Scalable Web Application on AWS

A multi-AZ, auto-scaling web application on AWS, defined entirely as Infrastructure as Code (Terraform).
A Flask REST API runs on EC2 instances behind an Application Load Balancer, backed by a Multi-AZ RDS MySQL database.

**Stack:** AWS EC2 · RDS (MySQL) · IAM · Auto Scaling Groups · ELB (ALB) · CloudWatch · VPC · Secrets Manager · Terraform · Python (Flask, SQLAlchemy, Gunicorn) · Locust

## Architecture
```
Internet -> ALB (public subnets, 2 AZs) -> ASG of EC2 (private subnets, 2 AZs) -> RDS MySQL Multi-AZ (isolated subnets)
                                              ^ CloudWatch alarms drive scale-out / scale-in
```
See [docs/architecture.md](docs/architecture.md) for design decisions.

## Key features
- **High availability:** EC2 spread across 2 AZs behind an ALB; ELB health checks auto-replace unhealthy instances; RDS Multi-AZ failover.
- **Elastic scaling:** ASG (min 2, max 6) with step-scaling policies triggered by CloudWatch CPU alarms; scale-in on sustained low CPU.
- **Database performance:** composite indexes matched to query patterns (`db/indexes.sql`), SQLAlchemy connection pooling with `pool_pre_ping` and recycling, slow-query log shipped to CloudWatch Logs.
- **Security:** least-privilege IAM role (read one secret, publish metrics to one namespace), DB password in Secrets Manager, security-group chaining (ALB -> EC2 -> RDS), IMDSv2 enforced, no SSH (use SSM Session Manager), encrypted storage.
- **Observability:** alarms for CPU, unhealthy hosts, RDS CPU and RDS connections.

## Project structure
```
app/         Flask API (+ pooled DB engine, Secrets Manager config)
db/          schema.sql (baseline), indexes.sql (optimised), seed.py
terraform/   VPC, subnets, ALB, ASG, RDS, IAM, CloudWatch
loadtest/    Locust scenario to trigger auto scaling
benchmarks/  Before/after query latency + pooled vs non-pooled
docs/        Architecture notes
```

## Deploy
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set repo_url to your GitHub repo
terraform init && terraform apply
```
Load schema once from an EC2 instance (SSM Session Manager) or a bastion:
```bash
mysql -h <rds_host> -u admin -p < db/schema.sql
DB_HOST=<rds_host> DB_SECRET_ARN=<db_secret_arn> python db/seed.py
```
Test: `curl http://<alb_dns>/health` and `curl "http://<alb_dns>/api/products?category=books&max_price=50"`.

**Cost note:** NAT Gateway, Multi-AZ RDS and the ALB are not free-tier. Run `terraform destroy` when finished.

## Measuring results (fill in YOUR numbers)
Run these and record real figures before quoting them anywhere.

**1. DB latency (indexing + pooling)**
```bash
python benchmarks/benchmark_queries.py --label baseline
mysql -h <rds_host> -u admin -p < db/indexes.sql
python benchmarks/benchmark_queries.py --label indexed
```
| Scenario | p50 | p95 |
|---|---|---|
| Baseline (no index, no pool) | _ms | _ms |
| Indexed + pooled | _ms | _ms |
| **Improvement** | _% | _% |

**2. Auto scaling under load**
```bash
locust -f loadtest/locustfile.py --host http://<alb_dns> -u 300 -r 20 -t 10m --headless
```
Start with ~100 users, spike to 300 (3x). Record: time to first scale-out, peak instance count, error rate, p95 response time.

**3. Uptime**
Use CloudWatch ALB metrics (`HTTPCode_Target_5XX_Count`, `RequestCount`) over the test window; availability = 1 - (5xx / total requests). Terminate an instance manually to demonstrate self-healing.

## Future improvements
HTTPS with ACM, CI/CD (GitHub Actions), ElastiCache for hot reads, read replicas, WAF.
