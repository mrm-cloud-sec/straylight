# terraform/modules/cdn/outputs.tf
# Outputs for the CDN module

output "cloudfront_domains" {
  description = "List of CloudFront distribution domain names (*.cloudfront.net)"
  value       = [for dist in aws_cloudfront_distribution.c2 : dist.domain_name]
}

output "cloudfront_distribution_ids" {
  description = "List of CloudFront distribution IDs"
  value       = [for dist in aws_cloudfront_distribution.c2 : dist.id]
}

output "c2_subdomain" {
  description = "The random subdomain created for this operation (e.g., a3f8c1d2e4b5.example.com)"
  value       = local.origin_domain
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name of the Route53 A record"
  value       = aws_route53_record.c2_subdomain.fqdn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

