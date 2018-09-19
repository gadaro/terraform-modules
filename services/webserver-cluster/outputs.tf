output "public_lb_dns" {
  value = "${aws_lb.example.dns_name}"
}

output "asg_name" {
  value = "${aws_autoscaling_group.example.name}"
}
