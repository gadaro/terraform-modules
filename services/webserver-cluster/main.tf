# Fetched from the provider
data "aws_availability_zones" "all" {}
data "aws_vpc" "selected" {}
data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.selected.id}"
}
data "terraform_remote_state" "db" {
  backend              = "s3"

  config {
    bucket             = "${var.db_remote_state_bucket}"
    key                = "${var.db_remote_state_key}"
    region             = "eu-west-3"
  }
}
data "template_file" "user_data" {
  count = "${1 - var.enable_new_user_data}"

  template             = "${file("${path.module}/user_data.sh")}"

  vars {
    server_port        = "${var.server_port}"
    db_address         = "${data.terraform_remote_state.db.address}"
    db_port            = "${data.terraform_remote_state.db.port}"
  }
}
data "template_file" "user_data_new" {
  count = "${var.enable_new_user_data}"

  template             = "${file("${path.module}/user-data-new.sh")}"

  vars {
    server_port        = "${var.server_port}"
  }
}

# LB across all subnets
resource "aws_lb" "example" {
    name               = "${var.cluster_name}-lb"
    security_groups    = ["${aws_security_group.lb.id}"]
    subnets            = ["${data.aws_subnet_ids.all.ids}"]
}

# Forward to target group
resource "aws_lb_listener" "example" {
    load_balancer_arn  = "${aws_lb.example.arn}"
    port               = "80"
    protocol           = "HTTP"

    default_action {
      type             = "forward"
      target_group_arn = "${aws_lb_target_group.example.arn}"
    }
}

resource "aws_lb_target_group" "example" {
    name               = "${var.cluster_name}-lb-tg"
    port               = "${var.server_port}"
    protocol           = "HTTP"
    vpc_id             = "${data.aws_vpc.selected.id}"

    health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 3
      path                = "/"
      interval            = 30
    }
}

# Autoscaling ------------------------------------------------------------------

resource "aws_autoscaling_group" "example" {
    launch_configuration = "${aws_launch_configuration.example.id}"
    availability_zones   = ["${data.aws_availability_zones.all.names}"]
    target_group_arns    = ["${aws_lb_target_group.example.arn}"]

    min_size = "${var.min_size}"
    max_size = "${var.max_size}"

    tag {
      key                 = "Name"
      value               = "${var.cluster_name}-asg"
      propagate_at_launch = true
    }
}

resource "aws_launch_configuration" "example" {
    image_id        = "ami-06340c8c12baa6a09"
    instance_type   = "${var.instance_type}"
    key_name        = "terraform-key"
    security_groups = ["${aws_security_group.instance.id}"]
    /* Rendered template file, replaced variables. Concat combines the two user_data
    lists, one of 0 length and one of 1 length. The last 0 returns the first element
    of the result of concat function */
    user_data = "${element(concat(data.template_file.user_data.*.rendered,
      data.template_file.user_data_new.*.rendered),0)}"

    # Creates a new launch configuration before destoying the former one
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_autoscaling_schedule" "scale_out_during_business_hours" {
  count = "${var.enable_autoscaling}"

  scheduled_action_name  = "scale_out_during_business_hours"
  min_size               = 2
  max_size               = 4
  desired_capacity       = 4
  recurrence             = "0 9 * * *"

  autoscaling_group_name = "${aws_autoscaling_group.example.name}"
}

resource "aws_autoscaling_schedule" "scale_in_at_night" {
  count = "${var.enable_autoscaling}"

  scheduled_action_name  = "scale_in_at_night"
  min_size               = 2
  max_size               = 4
  desired_capacity       = 2
  recurrence             = "0 17 * * *"

  autoscaling_group_name = "${aws_autoscaling_group.example.name}"
}

# Security groups --------------------------------------------------------------

resource "aws_security_group" "instance" {
    name = "${var.cluster_name}-i-sg"

    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group_rule" "allow_http_inbound_server" {
    type                     = "ingress"
    security_group_id        = "${aws_security_group.instance.id}"
    source_security_group_id = "${aws_security_group.lb.id}"

    from_port                = "${var.server_port}"
    to_port                  = "${var.server_port}"
    protocol                 = "tcp"
}

resource "aws_security_group_rule" "allow_all_outbound_server" {
    type              = "egress"
    security_group_id = "${aws_security_group.instance.id}"

    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "lb" {
    name = "${var.cluster_name}-lb-sg"

    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_security_group_rule" "allow_http_inbound_lb" {
    type              = "ingress"
    security_group_id = "${aws_security_group.lb.id}"

    from_port         = "${var.lb_port}"
    to_port           = "${var.lb_port}"
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_all_outbound_lb" {
    type              = "egress"
    security_group_id = "${aws_security_group.lb.id}"

    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
}

# Alarms -----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
    alarm_name = "${var.cluster_name}-high-cpu-utilization"
    namespace = "AWS/EC2"
    metric_name = "CPUUtilization"

    dimensions = {
      AutoScalingGroupName = "${aws_autoscaling_group.example.name}"
    }

    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 1
    period              = 300
    statistic           = "Average"
    threshold           = 90
    unit                = "Percent"
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_credit_balance" {
    # Extracts the first char of var.instance_type
    count = "${format("%.1s", var.instance_type) == "t" ? 1 : 0}"

    alarm_name = "${var.cluster_name}-low-cpu-credit-balance"
    namespace = "AWS/EC2"
    metric_name = "CPUCreditBalance"

    dimensions = {
      AutoScalingGroupName = "${aws_autoscaling_group.example.name}"
    }

    comparison_operator = "LessThanThreshold"
    evaluation_periods  = 1
    period              = 300
    statistic           = "Minimum"
    threshold           = 10
    unit                = "Count"
}
