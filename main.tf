terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "az" {
  state = "available"
}
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.az.names, 0, 2)
}

############ VPC (2 AZs: public + private app + private db) ############
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = { Name = "${var.project}-vpc" }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project}-public-${count.index}" }
}
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]
  tags = { Name = "${var.project}-app-${count.index}" }
}
resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = local.azs[count.index]
  tags = { Name = "${var.project}-db-${count.index}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id   # single NAT to limit cost; use one per AZ for full HA
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
resource "aws_route_table_association" "public" {
  count = 2
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "app" {
  count = 2
  subnet_id = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

############ Security groups (chain: internet -> ALB -> EC2 -> RDS) ############
resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-alb-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "app" {
  name_prefix = "${var.project}-app-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = 8000
    to_port = 8000
    protocol = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "db" {
  name_prefix = "${var.project}-db-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

############ RDS MySQL (Multi-AZ, password in Secrets Manager) ############
resource "aws_db_subnet_group" "db" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.db[*].id
}
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project}-mysql"
  family = "mysql8.0"
  parameter {
    name = "slow_query_log"
    value = "1"
  }
  parameter {
    name = "long_query_time"
    value = "0.5"
  }
  parameter {
    name = "performance_schema"
    value = "1"
    apply_method = "pending-reboot"
  }
}
resource "aws_db_instance" "mysql" {
  identifier                  = "${var.project}-mysql"
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  db_name                     = "appdb"
  username                    = "admin"
  manage_master_user_password = true   # password stored in Secrets Manager, never in code
  multi_az                    = true
  db_subnet_group_name        = aws_db_subnet_group.db.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  parameter_group_name        = aws_db_parameter_group.mysql.name
  storage_encrypted           = true
  backup_retention_period     = 7
  skip_final_snapshot         = true
  enabled_cloudwatch_logs_exports = ["slowquery", "error"]
}

############ IAM (least privilege) ############
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "app" {
  name = "app-least-privilege"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadOnlyDbSecret", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
        Resource = aws_db_instance.mysql.master_user_secret[0].secret_arn },
      { Sid = "PublishMetrics", Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*",
        Condition = { StringEquals = { "cloudwatch:namespace" = "ScalableWebApp" } } },
      { Sid = "WriteLogs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"],
        Resource = "arn:aws:logs:*:*:log-group:/${var.project}/*" }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {   # shell access via SSM instead of open SSH
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-profile"
  role = aws_iam_role.ec2.name
}

############ ALB ############
resource "aws_lb" "alb" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}
resource "aws_lb_target_group" "tg" {
  name     = "${var.project}-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  deregistration_delay = 30
  health_check {
    path = "/health"
    interval = 15
    healthy_threshold = 2
    unhealthy_threshold = 3
    matcher = "200"
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

############ Launch template + Auto Scaling Group ############
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }
  vpc_security_group_ids = [aws_security_group.app.id]
  metadata_options { http_tokens = "required" }   # IMDSv2 only
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url   = var.repo_url
    db_host    = aws_db_instance.mysql.address
    secret_arn = aws_db_instance.mysql.master_user_secret[0].secret_arn
    region     = var.region
  }))
}
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.project}-asg"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 6
  vpc_zone_identifier       = aws_subnet.app[*].id   # spans both AZs
  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180
  launch_template {
    id = aws_launch_template.app.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
  tag {
    key = "Name"
    value = "${var.project}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name = "scale-out"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type = "StepScaling"
  adjustment_type = "ChangeInCapacity"
  step_adjustment {
    scaling_adjustment = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20
  }
  step_adjustment {
    scaling_adjustment = 2
    metric_interval_lower_bound = 20
  }
}
resource "aws_autoscaling_policy" "scale_in" {
  name = "scale-in"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  policy_type = "SimpleScaling"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 300
}

############ CloudWatch alarms ############
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name = "${var.project}-cpu-high"
  namespace = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic = "Average"
  period = 60
  evaluation_periods = 2
  threshold = 60
  comparison_operator = "GreaterThanThreshold"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.asg.name }
  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name = "${var.project}-cpu-low"
  namespace = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic = "Average"
  period = 300
  evaluation_periods = 3
  threshold = 25
  comparison_operator = "LessThanThreshold"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.asg.name }
  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name = "${var.project}-unhealthy-hosts"
  namespace = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic = "Maximum"
  period = 60
  evaluation_periods = 2
  threshold = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = { TargetGroup = aws_lb_target_group.tg.arn_suffix, LoadBalancer = aws_lb.alb.arn_suffix }
}
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name = "${var.project}-rds-cpu"
  namespace = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic = "Average"
  period = 300
  evaluation_periods = 2
  threshold = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions = { DBInstanceIdentifier = aws_db_instance.mysql.identifier }
}
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name = "${var.project}-rds-connections"
  namespace = "AWS/RDS"
  metric_name = "DatabaseConnections"
  statistic = "Maximum"
  period = 60
  evaluation_periods = 2
  threshold = 60
  comparison_operator = "GreaterThanThreshold"
  dimensions = { DBInstanceIdentifier = aws_db_instance.mysql.identifier }
}
