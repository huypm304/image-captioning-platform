resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }
}

resource "aws_acm_certificate" "wildcard" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.resource_record_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "jenkins" {
  count   = var.jenkins_vps_ip != "" ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "jenkins.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.jenkins_vps_ip]
}
