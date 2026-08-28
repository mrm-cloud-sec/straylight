# terraform/modules/cdn/main.tf
# CloudFront distributions and Route53 DNS for domain fronting

# Look up the existing hosted zone for the domain
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Random subdomain — avoids leaking operation name in DNS
resource "random_id" "subdomain" {
  byte_length = 6
}

locals {
  dns_subdomain = random_id.subdomain.hex
  origin_domain = "${local.dns_subdomain}.${var.domain_name}"
}

# Create A record for the operation subdomain pointing to redirector
resource "aws_route53_record" "c2_subdomain" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.origin_domain
  type    = "A"
  ttl     = 300
  records = [var.redirector_public_ip]
}

# Use AWS managed CachingDisabled policy
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Use AWS managed AllViewer origin request policy (forwards all headers, cookies, query strings)
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# CloudFront distributions
resource "aws_cloudfront_distribution" "c2" {
  count = var.distribution_count

  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.operation_name} C2 distribution ${count.index + 1}"
  price_class     = var.price_class

  origin {
    domain_name = local.origin_domain
    origin_id   = "c2-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      
      # Timeouts for C2 traffic (longer for potential large payloads)
      origin_read_timeout      = 60
      origin_keepalive_timeout = 60
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "c2-origin"

    # Use AWS managed policies
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    viewer_protocol_policy = "https-only"
    compress               = true
  }

  # No geo restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use default CloudFront certificate (*.cloudfront.net) - FREE
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name      = "${var.operation_name}-cloudfront-${count.index + 1}"
    Operation = var.operation_name
  }

  # Wait for the DNS record to be created first
  depends_on = [aws_route53_record.c2_subdomain]
}
