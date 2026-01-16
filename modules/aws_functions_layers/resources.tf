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

## ---------------------------------------------------------------------------------------------------------------------
## NULL RESOURCE
##
## Install the Python dependency with Pip
## ---------------------------------------------------------------------------------------------------------------------
resource "null_resource" "this" {
  for_each = { for package in var.layer_packages : package.package_name => package }

  provisioner "local-exec" {
    command = "pip install ${each.value.no_dependencies ? "--no-deps" : ""} --upgrade --target ./source/${var.layer_name}/python ${each.value.package_name}==${each.value.package_version}"
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## ARCHIVE FILE DATA SOURCE
##
## Zip the Python package for upload to AWS Storage Bucket.
## https://docs.aws.amazon.com/lambda/latest/dg/python-package.html
## https://docs.aws.amazon.com/lambda/latest/dg/packaging-layers.html
##
## Parameters:
## - `type`: Archive file type
## - `source_dir`: Dependency package path.
## - `output_file_mode`: Unix permission
## - `output_path`: Archive output path
## ---------------------------------------------------------------------------------------------------------------------
data "archive_file" "this" {
  type             = "zip"
  source_dir       = "./source/${var.layer_name}"
  output_file_mode = "0666"
  output_path      = "./source/${var.layer_name}.zip"

  depends_on = [null_resource.this]
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS S3 OBJECT RESOURCE
##
## Upload the dependency artifact to S3 Function Source bucket.
##
## Parameters:
## - `bucket`: AWS S3 Function Source bucket.
## - `key`: S3 Blob name for dependency package artifact.
## - `source`: Filepath to depenency package artifact.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_object" "this" {
  provider   = aws.auth_session
  depends_on = [data.archive_file.this]

  bucket = var.bucket_id
  key    = "layer_${var.layer_name}.zip"
  source = data.archive_file.this.output_path
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS LAMBDA LAYER VERSION RESOURCE
##
## Provides a Lambda Layer Version resource. Lambda Layers allow you to
## reuse shared bits of code across multiple lambda functions.
##
## Parameters:
## - `layer_name`: AWS Lambda Function layer name.
## - `s3_bucket`: S3 Function source code bucket.
## - `s3_key`: S3 Blob name to dependency package artifact.
## - `compatible_runtimes`: List of Lambda Function runtime environemts to mark as verions.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_lambda_layer_version" "this" {
  provider = aws.auth_session

  layer_name          = "layer_${var.layer_name}"
  s3_bucket           = var.bucket_id
  s3_key              = aws_s3_object.this.key
  compatible_runtimes = [var.function_runtime]
}
