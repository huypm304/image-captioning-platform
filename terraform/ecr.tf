resource "aws_ecr_repository" "app" {
  name                 = "cms-devops-dev-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Project     = "cms-devops"
    Environment = "dev"
  }
}
