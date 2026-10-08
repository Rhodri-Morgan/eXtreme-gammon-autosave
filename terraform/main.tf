terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  bucket = "prod-eu-west-1-app-data"
  prefix = "backgammon/"
}

resource "aws_iam_user" "xg_autosave" {
  name = "xg-autosave"
}

resource "aws_iam_user_policy" "xg_autosave" {
  name = "s3-backgammon-write"
  user = aws_iam_user.xg_autosave.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "arn:aws:s3:::${local.bucket}/${local.prefix}*"
    }]
  })
}

resource "aws_iam_access_key" "xg_autosave" {
  user = aws_iam_user.xg_autosave.name
}

output "access_key_id" {
  value = aws_iam_access_key.xg_autosave.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.xg_autosave.secret
  sensitive = true
}
