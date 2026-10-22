output "alb_dns" {
  value = aws_lb.alb.dns_name
}
output "rds_host" {
  value = aws_db_instance.mysql.address
}
output "db_secret_arn" {
  value = aws_db_instance.mysql.master_user_secret[0].secret_arn
}
