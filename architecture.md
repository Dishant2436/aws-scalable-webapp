# Architecture

```
Internet
   |
[ Application Load Balancer ]  (public subnets, AZ-a + AZ-b)
   |
[ Auto Scaling Group: 2-6 EC2 ]  (private app subnets, AZ-a + AZ-b)
   |
[ RDS MySQL Multi-AZ ]  (private DB subnets, primary + standby)

CloudWatch alarms -> ASG scaling policies
IAM role (least privilege) on EC2 -> Secrets Manager (DB password) + CloudWatch
```

| Layer | Design decision |
|---|---|
| VPC | 3 subnet tiers across 2 AZs; only the ALB is internet-facing |
| Security groups | ALB -> EC2:8000 -> RDS:3306, each referencing the previous SG |
| Compute | EC2 in ASG, ELB health checks replace failed instances automatically |
| Scaling | Step-scaling policies triggered by CloudWatch CPU alarms |
| Database | Multi-AZ RDS (automatic failover), encrypted, slow-query log on |
| Security | Least-privilege IAM, no hardcoded secrets, IMDSv2, no open SSH (SSM) |
