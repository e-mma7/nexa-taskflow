
# Ce code est destiné à l'analyse de sécurité Checkov.
# Ne pas appliquer sans adapter et vérifier la configuration AWS.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}

provider "aws" {
  alias  = "replica"
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

# --------------------------------------------------
# VARIABLES
# --------------------------------------------------

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# --------------------------------------------------
# KMS - CHIFFREMENT
# --------------------------------------------------

resource "aws_kms_key" "s3" {
  description             = "KMS key for TaskFlow S3"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "KMS key for TaskFlow S3 replica"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "database" {
  description             = "KMS key for TaskFlow database"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

# --------------------------------------------------
# S3 - BUCKET PRINCIPAL
# --------------------------------------------------

resource "aws_s3_bucket" "exports" {
  bucket = "taskflow-exports-demo"
}

resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "exports" {
  bucket = aws_s3_bucket.exports.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id

  rule {
    id     = "taskflow-exports-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# --------------------------------------------------
# S3 - BUCKET DE JOURNALISATION
# --------------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket = "taskflow-exports-access-logs-demo"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3ServerAccessLogging"
      Effect    = "Allow"
      Principal = {
        Service = "logging.s3.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.logs.arn}/access-logs/*"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = aws_s3_bucket.exports.arn
        }
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_s3_bucket_logging" "exports" {
  bucket        = aws_s3_bucket.exports.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "access-logs/"
}

# --------------------------------------------------
# S3 - BUCKET DE REPLICATION INTER-REGION
# --------------------------------------------------

resource "aws_s3_bucket" "replica" {
  provider = aws.replica
  bucket   = "taskflow-exports-replica-demo"
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.replica.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  rule {
    id     = "replica-lifecycle"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# --------------------------------------------------
# IAM - AUTORISATION DE REPLICATION
# --------------------------------------------------

resource "aws_iam_role" "replication" {
  name = "taskflow-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "taskflow-s3-replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.exports.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.exports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.replica.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.replica.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "exports" {
  depends_on = [
    aws_s3_bucket_versioning.exports,
    aws_s3_bucket_versioning.replica,
    aws_iam_role_policy.replication
  ]

  bucket = aws_s3_bucket.exports.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-exports"
    status = "Enabled"

    filter {}

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

# --------------------------------------------------
# EC2 - SERVEUR API
# --------------------------------------------------

resource "aws_security_group" "web" {
  name        = "taskflow-web"
  description = "Acces a l API TaskFlow"

  ingress {
    description = "SSH depuis le reseau prive uniquement"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }

  ingress {
    description = "API TaskFlow depuis le reseau prive"
    from_port   = 8085
    to_port     = 8085
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "api" {
  ami                    = "ami-0123456789abcdef0"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "taskflow-api"
  }
}

# --------------------------------------------------
# RDS - BASE DE DONNEES
# --------------------------------------------------

resource "aws_db_instance" "tasks" {
  identifier              = "taskflow-db"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "taskflow"
  password                = var.db_password
  publicly_accessible     = false
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.database.arn
  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
}
