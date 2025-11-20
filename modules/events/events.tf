resource "aws_sns_topic" "events" {
  name = "${var.project_name}-${var.env}-events"
}
