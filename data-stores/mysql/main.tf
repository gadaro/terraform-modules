resource "aws_db_instance" "example" {
  engine              = "mysql"
  allocated_storage   = "${var.db_storage}"
  instance_class      = "${var.db_instance}"
  name                = "${var.db_name}"
  username            = "admin"
  password            = "${var.db_password}"
  skip_final_snapshot = true
}
