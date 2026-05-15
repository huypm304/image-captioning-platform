variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "image-caption-dev-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "domain_name" {
  description = "Root domain managed in Route53"
  type        = string
  default     = "minhhuy.me"
}

variable "jenkins_vps_ip" {
  description = "Public IP of the Jenkins VPS (leave empty to skip DNS record)"
  type        = string
  default     = ""
}
