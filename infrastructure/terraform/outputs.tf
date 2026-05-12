output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster auth"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (for IAM roles for service accounts)"
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_url" {
  description = "ECR image URI prefix (registry/repo) for docker push/pull"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_registry_host" {
  description = "ECR registry hostname only (useful for docker login)"
  value       = split("/", aws_ecr_repository.app.repository_url)[0]
}

output "models_bucket" {
  description = "S3 bucket for models/ artifacts (sync via infrastructure/scripts/08-upload-models.sh)"
  value       = aws_s3_bucket.models.bucket
}

output "demo_app_role_arn" {
  description = "IAM role ARN for IRSA (ServiceAccount default/demo-app)"
  value       = aws_iam_role.demo_app.arn
}

output "frontend_ecr_repository_url" {
  description = "ECR image URI prefix for the frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "route53_nameservers" {
  description = "NS records to configure at Namecheap for minhhuy.me"
  value       = aws_route53_zone.main.name_servers
}

output "acm_certificate_arn" {
  description = "ACM wildcard certificate ARN for ALB HTTPS"
  value       = aws_acm_certificate.wildcard.arn
}
