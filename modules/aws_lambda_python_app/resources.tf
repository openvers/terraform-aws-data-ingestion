terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      configuration_aliases = [
        aws.auth_session,
      ]
    }
  }
}

data "aws_caller_identity" "auth_session" {
  provider = aws.auth_session
}

data "aws_region" "current" {
  provider = aws.auth_session
}

locals {
  service_principal_arn = data.aws_caller_identity.auth_session.arn

  policy_bucket_actions = [
    "s3:GetObject",
    "s3:PutObject"
  ]

  policy_cloudwatch_actions = [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ]

  #https://github.com/awslabs/aws-lambda-web-adapter?tab=readme-ov-file#lambda-functions-packaged-as-zip-package-for-aws-managed-runtimes
  layer_arns = concat(
    [for d in module.function_layers : d.layer_arn],
    ["arn:aws:lambda:${data.aws_region.current.region}:753240598075:layer:LambdaAdapterLayerX86:25"]
  )

  function_environment_variables = merge(var.function_environment_variables, {
    AWS_LAMBDA_EXEC_WRAPPER = "/opt/bootstrap"
    PORT : 8000
  })
}

## ---------------------------------------------------------------------------------------------------------------------
## ARCHIVE FILE DATA SOURCE
##
## Zip the latest changes to the function source code prior to deployment.
##
## Parameters:
## - `type`: Archive file type
## - `output_file_mode`: Unix permission
## - `output_path`: Archive output path
## - `content`: Dynamic source code file paths to compressed in archive
## - `filename`: Dynamic source code file names to be mapped in compressed archive
## ---------------------------------------------------------------------------------------------------------------------
data "archive_file" "this" {
  type             = "zip"
  output_file_mode = "0666"
  output_path      = "./source/${var.function_name}.zip"

  dynamic "source" {
    for_each = var.function_contents
    content {
      content  = file(source.value.filepath) # Path to File
      filename = source.value.filename       # Name of file in zip file
    }
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## FUNCTION BUCKET MODULE
##
## S3 Bucket to store AWS Lambda Function source code.
##
## Parameters:
## - `bucket_name`: S3 bucket name.
## - `kms_key_arn`: KMS encryption key ARN.
## - `sns_topic_arn`: AWS SNS Topic ARN.
## ---------------------------------------------------------------------------------------------------------------------
module "function_bucket" {
  source = "github.com/openvers/terraform-aws-data-lake.git//modules/s3_bucket?ref=496c43258348e41337cf35a8d0c784b5fb606b8d"

  bucket_name = var.function_bucket_name
  kms_key_arn = var.kms_key_arn

  providers = {
    aws.auth_session = aws.auth_session
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS S3 OBJECT RESOURCE
##
## Upload the pipeline source code to trigger on every new blob upload on the trigger bucket.
##
## Parameters:
## - `bucket`: S3 Bucket name where function source code will reside
## - `key`: Blob name for function source code artifact
## - `source`: File path to function source code zip archive
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_object" "this" {
  provider = aws.auth_session

  bucket = module.function_bucket.bucket_id
  key    = "${var.function_name}.zip"
  source = data.archive_file.this.output_path
}

## ---------------------------------------------------------------------------------------------------------------------
## FUNCTION LAYERS MODULE
##
## Create AWS Lambda Function layers for source code dependencies.
##
## Parameters:
## - `bucket_id`: S3 Bucket name where function source code resides.
## - `package_name`: PIP package name.
## - `package_version`: PIP package version.
## - `function_runtime`: AWS Lamdba Function runtime environment.
## ---------------------------------------------------------------------------------------------------------------------
module "function_layers" {
  source   = "../aws_functions_layers"
  for_each = var.function_dependencies

  bucket_id        = module.function_bucket.bucket_id
  layer_name       = each.key
  layer_packages   = each.value
  function_runtime = var.function_runtime

  providers = {
    aws.auth_session = aws.auth_session
  }
}


## ---------------------------------------------------------------------------------------------------------------------
## AWS IAM POLICY DOCUMENT DATA SOURCE
##
## Define a policy document to grant assume role STS permissions to Lambda Function Resource Principals.
## ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  provider = aws.auth_session

  statement {
    sid     = "PolicyDoc${replace("${var.function_name}AssumeRole", "-", "")}"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}


## ---------------------------------------------------------------------------------------------------------------------
## AWS IAM ROLE RESOURCE
##
## Create a Lambda Function Role to assume policies for STS authentication.
##
## Parameters:
## - `name`: AWS IAM Role name.
## - `assume_role_policy`: AWS IAM Policy document JSON.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  provider = aws.auth_session

  name               = substr("${var.function_name}-role", 0, 64) # AWS IAM Role names are limited to 64 characters
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}


## ---------------------------------------------------------------------------------------------------------------------
## AWS CLOUDWATCH LOG GROUP RESOURCE
##
## Create a Logging Group for the Lamdba Function to stream function execution logs to Cloud Watch.
## Without this resource, logs are stored indefinitely
##
## Parameters:
## - `name`: AWS IAM Role name.
## - `retention_in_days`: AWS Cloudwatch Logs retention period in days.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  provider = aws.auth_session

  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days
}


## ---------------------------------------------------------------------------------------------------------------------
## AWS IAM POLICY DOCUMENT DATA SOURCE
##
## Define a policy document to grant resource access to S3 buckets, Cloudwatch logging, and SNS Publishing.
## ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "logs" {
  provider = aws.auth_session

  statement {
    sid    = "${replace(title(replace("${var.function_name}", "-", " ")), " ", "")}S3PolicyDoc"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = flatten([
      for bucket_id in var.bucket_ids : [
        "arn:aws:s3:::${bucket_id}",
        "arn:aws:s3:::${bucket_id}/*"
      ]
    ])
  }

  statement {
    sid    = "${replace(title(replace("${var.function_name}", "-", " ")), " ", "")}LogsPolicyDoc"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      aws_cloudwatch_log_group.this.arn,
      "${aws_cloudwatch_log_group.this.arn}:*"
    ]
  }

  statement {
    sid     = "${replace(title(replace("${var.function_name}", "-", " ")), " ", "")}SNSPolicyDoc"
    effect  = "Allow"
    actions = ["sns:*"]

    resources = [
      var.sns_topic_arn,
    ]
  }

  statement {
    sid    = "${replace(title(replace("${var.function_name}", "-", " ")), " ", "")}KMSPolicyDoc"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Encrypt",
      "kms:Decrypt",
    ]

    resources = [
      var.kms_key_arn,
    ]
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS IAM ROLE POLICY RESOURCE
##
## Bind AWS Lambda Function role with logs policy.
##
## Parameters:
## - `name`: AWS IAM Role policy name.
## - `role`: AWS IAM Role ID.
## - `policy`: AWS IAM Policy document JSON.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role_policy" "this" {
  provider = aws.auth_session

  name   = "${replace(title(replace("${var.function_name}", "-", " ")), " ", "")}RolePolicy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logs.json
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS LAMBDA FUNCTION RESOURCE
##
## Defines the ETL function to convert data in the Trigger Bucket to
## Parquet Format in the Results Bucket.
##
## Parameters:
## - `function_name`: AWS Lambda Function name.
## - `role`: Lambda Function role.
## - `handler`: Lambda Function handler name.
## - `runtime`: Lambda Function environment runtime.
## - `s3_bucket`: AWS S3 bucket contiaing function source.
## - `s3_key`: AWS S3 blob containing function source code base artifact.
## - `memory_size`: Allocated RAM for Lambda Function in MBs.
## - `timeout`: Lambda Function timeout in seconds.
## - `layers`: AWS Lambda Function extra dependency layers.
## - `variables`: AWS Lambda Function ENV Variables.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_lambda_function" "this" {
  provider = aws.auth_session

  function_name = var.function_name
  role          = aws_iam_role.this.arn
  handler       = var.function_handler
  runtime       = var.function_runtime
  s3_bucket     = module.function_bucket.bucket_id
  s3_key        = aws_s3_object.this.key
  memory_size   = var.function_memory
  timeout       = var.function_timeout
  layers        = local.layer_arns
  kms_key_arn   = var.kms_key_arn

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  environment {
    variables = local.function_environment_variables
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = var.sns_topic_arn
  }

  depends_on = [
    aws_cloudwatch_log_group.this
  ]
}
