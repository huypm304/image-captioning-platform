data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "models" {
  bucket        = "image-caption-dev-models-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project     = "image-caption"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket = aws_s3_bucket.models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
