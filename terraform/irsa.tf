locals {
  app_namespace      = "default"
  app_serviceaccount = "demo-app"
  oidc_provider      = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "demo_app_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.app_namespace}:${local.app_serviceaccount}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "demo_app" {
  name               = "cms-devops-dev-demo-app"
  assume_role_policy = data.aws_iam_policy_document.demo_app_assume.json

  tags = {
    Project     = "cms-devops"
    Environment = "dev"
  }
}

data "aws_iam_policy_document" "demo_app_s3" {
  statement {
    sid    = "ListModelsBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.models.arn]
  }

  statement {
    sid    = "GetModelObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.models.arn}/*"]
  }
}

resource "aws_iam_role_policy" "demo_app_s3" {
  name   = "cms-devops-dev-demo-app-s3-models"
  role   = aws_iam_role.demo_app.id
  policy = data.aws_iam_policy_document.demo_app_s3.json
}
