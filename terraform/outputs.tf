output "alb_dns_name" {
  description = "Public URL of the load balancer — open this in your browser"
  value       = "http://${aws_lb.main.dns_name}"
}
