module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  enable_irsa = true

  enable_cluster_creator_admin_permissions = true

  # Dev: 3 nodes reduces "Too many pods" / Pending (Argo controller, monitoring, app, ALB targets).
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 3
      ami_type       = "AL2_x86_64"
    }
  }

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }
}
