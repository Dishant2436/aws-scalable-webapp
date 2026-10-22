variable "region" {
  default = "ap-south-1"
}
variable "project" {
  default = "scalable-webapp"
}
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "instance_type" {
  default = "t3.micro"
}
variable "db_instance_class" {
  default = "db.t3.micro"
}
variable "repo_url" {
  description = "Git URL of this repo (EC2 clones it at boot)"
}
