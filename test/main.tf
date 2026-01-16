terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  backend "remote" {
    # The name of your Terraform Cloud organization.
    organization = "sim-parables"

    # The name of the Terraform Cloud workspace to store Terraform state files in.
    workspaces {
      name = "ci-cd-aws-workspace"
    }
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## RANDOM STRING RESOURCE
##
## This resource generates a random string of a specified length.
##
## Parameters:
## - `special`: Whether to include special characters in the random string.
## - `upper`: Whether to include uppercase letters in the random string.
## - `length`: The length of the random string.
## ---------------------------------------------------------------------------------------------------------------------
resource "random_string" "this" {
  special = false
  upper   = false
  numeric = false
  length  = 4
}

locals {
  assume_role_policies = [
    {
      effect = "Allow"
      actions = [
        "sts:AssumeRoleWithWebIdentity"
      ]
      principals = [{
        type        = "Federated"
        identifiers = [var.OIDC_PROVIDER_ARN]
      }]
      conditions = [
        {
          test     = "StringLike"
          variable = "token.actions.githubusercontent.com:sub"
          values = [
            "repo:${var.GITHUB_REPOSITORY}:ref:${var.GITHUB_REF}"
          ]
        },
        {
          test     = "ForAllValues:StringEquals"
          variable = "token.actions.githubusercontent.com:iss"
          values = [
            "https://token.actions.githubusercontent.com",
          ]
        },
        {
          test     = "ForAllValues:StringEquals"
          variable = "token.actions.githubusercontent.com:aud"
          values = [
            "sts.amazonaws.com",
          ]
        },
      ]
    },
    {
      effect = "Allow"
      actions = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      principals = [{
        type        = "AWS"
        identifiers = [module.aws_service_account.service_account_arn]
      }]
      conditions = []
    }
  ]

  service_account_roles_list = [
    "iam:DeleteRole",
    "iam:ListInstanceProfilesForRole",
    "iam:ListAttachedRolePolicies",
    "iam:ListRolePolicies",
    "iam:AttachRolePolicy",
    "iam:TagRole",
    "iam:GetRole",
    "iam:CreateRole",
    "iam:PassRole",
    "iam:CreatePolicy",
    "iam:GetPolicy",
    "iam:GetRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:GetPolicyVersion",
    "iam:ListPolicyVersions",
    "iam:DetachRolePolicy",
    "iam:DeletePolicy",
    "iam:CreatePolicyVersion",
    "iam:DeletePolicyVersion",
    "iam:ListAttachedGroupPolicies",
    "iam:AttachGroupPolicy",
    "iam:GetGroupPolicy",
    "iam:PutGroupPolicy",
    "iam:DeleteGroupPolicy",
    "iam:DetachGroupPolicy",
    "kms:ScheduleKeyDeletion",
    "kms:GenerateDataKey*",
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "s3:*",
    "s3-object-lambda:*",
    "lambda:*",
    "logs:*",
    "sns:*",
    "apigateway:*"
  ]

  suffix = "test-${random_string.this.id}"
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS PROVIDER
##
## Configures the AWS provider with CLI Credentials.
## ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  alias = "accountgen"
}

##---------------------------------------------------------------------------------------------------------------------
## AWS SERVICE ACCOUNT MODULE
##
## This module provisions an AWS service account along with associated roles and security groups.
##
## Parameters:
## - `service_account_name`: The display name of the new AWS Service Account.
## - `service_account_path`: The new AWS Service Account IAM Path.
## - `roles_list`: List of IAM roles to bing to new AWS Service Account.
##---------------------------------------------------------------------------------------------------------------------
module "aws_service_account" {
  source = "github.com/openvers/terraform-aws-service-account.git?ref=6ba54cf0fece6e4f2fbbfae5dacb9d7e91e984bb"

  service_account_name = var.service_account_name
  service_account_path = var.service_account_path
  roles_list           = local.service_account_roles_list

  providers = {
    aws.accountgen = aws.accountgen
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS PROVIDER
##
## Configures the AWS provider with new Service Account Authentication.
## ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  alias = "auth_session"

  access_key = module.aws_service_account.access_id
  secret_key = module.aws_service_account.access_token
}

##---------------------------------------------------------------------------------------------------------------------
## AWS IDENTITY FEDERATION ROLES MODULE
##
## This module configured IAM Trust policies to provide OIDC federated access from Github Actions to AWS.
##
## Parameters:
## - `assume_role_policies`: List of OIDC trust policies.
##---------------------------------------------------------------------------------------------------------------------
module "aws_identity_federation_roles" {
  source     = "github.com/openvers/terraform-aws-service-account.git//modules/identity_federation_roles?ref=a18e50b961655a345a7fd2d8e573fe84484c7235"
  depends_on = [module.aws_service_account]

  assume_role_policies  = local.assume_role_policies
  service_account_group = module.aws_service_account.group_name
  policy_roles_list = [
    "iam:DeleteRole",
    "iam:ListInstanceProfilesForRole",
    "iam:ListAttachedRolePolicies",
    "iam:ListRolePolicies",
    "iam:GetRole",
    "iam:CreateRole",
    "iam:GetRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:CreatePolicyVersion",
    "iam:DeletePolicyVersion",
    "s3:Get*",
    "s3:Put*",
    "s3:List*",
    "kms:GenerateDataKey*",
    "kms:Encrypt",
    "kms:Decrypt",
    "apigateway:*",
  ]

  providers = {
    aws.auth_session = aws.auth_session
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## SNS TOPIC MODULE
##
## Create an AWS SNS Topic.
##
## Parameters:
## - `kms_key_id`: KMS key name.
## ---------------------------------------------------------------------------------------------------------------------
module "sns_topic" {
  source = "../modules/aws_sns_topic"

  sns_topic_name = "${local.suffix}-sns-topic"
  kms_key_id     = module.data_lake.kms_key_id

  providers = {
    aws.auth_session = aws.auth_session
  }
}


## ---------------------------------------------------------------------------------------------------------------------
## DATA LAKE MODULE
##
## Provisions a complete AWS Data Lake environment, including S3 buckets for bronze, silver, and gold medallion data layers,
## IAM roles and policies, KMS encryption, Lambda function integration, and supporting resources.
##
## Parameters:
## - `bronze_bucket_name`: Name of the S3 bucket for raw/bronze data.
## - `silver_bucket_name`: Name of the S3 bucket for processed/silver data.
## - `gold_bucket_name`: Name of the S3 bucket for curated/gold data.
##
## Notes:
## - This module is designed for end-to-end data lake testing and development.
## - Additional configuration may be required for Lambda, KMS, and IAM integration depending on your use case.
## ---------------------------------------------------------------------------------------------------------------------
module "data_lake" {
  source     = "github.com/openvers/terraform-aws-data-lake.git?ref=496c43258348e41337cf35a8d0c784b5fb606b8d"
  depends_on = [module.aws_service_account]

  bronze_bucket_name = "${local.suffix}-bronze"
  silver_bucket_name = "${local.suffix}-silver"
  gold_bucket_name   = "${local.suffix}-gold"

  providers = {
    aws.auth_session = aws.auth_session
  }
}


## ---------------------------------------------------------------------------------------------------------------------
## AWS LAMBDA FUNCTION MODULE
##
## Create a HTTP trigger AWS Lambda Function for Data Ingestion into S3 Data Lake.
##
## Parameters:
## - `function_name`: AWS Lambda Function name.
## - `function_handler`: AWS Lambda Function source handler function name.
## - `bronze_bucket_id`: S3 Bucket name for the bronze data layer.
## - `function_runtime`: AWS Lambda Function runtime environment.
## - `kms_key_arn`: KMS encryption key ARN.
## - `sns_topic_arn`: SNS Topic ARN for Dead Letter Queue.
## - `function_contents`: List of function source code to archive and artifact for Lambda Functions.
## - `function_dependencies`: List of Python packages to install as dependencies for the Lambda Function.
## - `function_environment_variables`: Environment variables to set for the Lambda Function.
## ---------------------------------------------------------------------------------------------------------------------
module "aws_lambda_function" {
  source = "../"
  depends_on = [
    module.data_lake,
    module.aws_identity_federation_roles
  ]

  function_name    = "${local.suffix}-data-ingestion-lambda"
  function_handler = "run.sh"
  sns_topic_arn    = module.sns_topic.sns_topic_arn
  kms_key_arn      = module.data_lake.kms_key_arn
  bucket_ids       = [module.data_lake.bronze_bucket_id]

  function_contents = [
    {
      filename = "main.py",
      filepath = abspath("./source/main.py")
    },
    {
      filename = "requirements.txt",
      filepath = abspath("./source/requirements.txt")
    },
    {
      filename = "run.sh",
      filepath = abspath("./source/run.sh")
    }
  ]

  function_dependencies = {
    file_system = [
      {
        package_name    = "s3fs",
        package_version = "2025.12.0",
        no_dependencies = false
      },
      {
        package_name    = "fsspec",
        package_version = "2025.12.0",
        no_dependencies = false
      },
      {
        package_name    = "typing-extensions",
        package_version = "4.10.0",
        no_dependencies = false
      },
    ],
    web_app = [
      {
        package_name    = "flask",
        package_version = "3.1.2",
        no_dependencies = false
      },
      {
        package_name    = "gunicorn",
        package_version = "23.0.0",
        no_dependencies = false
      }
    ]
  }

  function_environment_variables = {
    TARGET_BUCKET = module.data_lake.bronze_bucket_id
  }

  providers = {
    aws.auth_session = aws.auth_session
  }
}
