resource "aws_ecr_repository" "app" {
  name                 = "image-caption-dev-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "image-caption-dev-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }
}
