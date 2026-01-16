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
## AWS LAMBDA FUNCTION MODULE
##
## Create a HTTP trigger AWS Lambda Function for Data Ingestion into S3 Data Lake.
##
## Parameters:
## - `function_name`: AWS Lambda Function name.
## - `function_handler`: AWS Lambda Function source handler function name.
## - `bucket_ids`: List of S3 Bucket names for the data layers.
## - `function_runtime`: AWS Lambda Function runtime environment.
## - `kms_key_arn`: KMS encryption key ARN.
## - `sns_topic_arn`: SNS Topic ARN for Dead Letter Queue.
## - `function_contents`: List of function source code to archive and artifact for Lambda Functions.
## - `function_dependencies`: List of Python packages to install as dependencies for the Lambda Function.
## - `function_environment_variables`: Environment variables to set for the Lambda Function.
## ---------------------------------------------------------------------------------------------------------------------
module "aws_lambda_function" {
  source = "./modules/aws_lambda_python_app"

  function_name                  = var.function_name
  function_handler               = var.function_handler
  sns_topic_arn                  = var.sns_topic_arn
  kms_key_arn                    = var.kms_key_arn
  bucket_ids                     = var.bucket_ids
  function_contents              = var.function_contents
  function_dependencies          = var.function_dependencies
  function_environment_variables = var.function_environment_variables
  function_bucket_name           = var.function_bucket_name
  function_trigger_events        = var.function_trigger_events
  function_runtime               = var.function_runtime

  providers = {
    aws.auth_session = aws.auth_session
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY REST API RESOURCE
##
## Create an API Gateway REST API to trigger the Lambda function via HTTP request.
##
## Parameters:
## - `name`: API Gateway REST API name.
## - `description`: API Gateway REST API description.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "this" {
  provider = aws.auth_session

  name        = "${var.function_name}-api"
  description = "API Gateway for Lambda HTTP trigger"
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY RESOURCE
##
## Define a resource in the API Gateway REST API.
##
## Parameters:
## - `rest_api_id`: The ID of the REST API.
## - `parent_id`: The ID of the parent resource.
## - `path_part`: The last part of the resource path.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_resource" "this" {
  provider = aws.auth_session

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY METHOD RESOURCE
##
## Define a method for the API Gateway resource.
##
## Parameters:
## - `rest_api_id`: The ID of the REST API.
## - `resource_id`: The ID of the resource.
## - `http_method`: The HTTP method.
## - `authorization`: The authorization type.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_method" "this" {
  provider = aws.auth_session

  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.this.id
  http_method      = var.api_method
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY INTEGRATION RESOURCE
##
## Define an integration for the API Gateway method.
##
## Parameters:
## - `rest_api_id`: The ID of the REST API.
## - `resource_id`: The ID of the resource.
## - `http_method`: The HTTP method.
## - `integration_http_method`: The integration HTTP method.
## - `type`: The integration type.
## - `uri`: The URI of the integration endpoint.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_integration" "this" {
  provider = aws.auth_session

  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.this.id
  http_method             = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  passthrough_behavior    = "WHEN_NO_MATCH"
  uri                     = module.aws_lambda_function.lambda_function_invoke_arn
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS LAMBDA PERMISSION RESOURCE
##
## Grant API Gateway permission to invoke the Lambda function.
##
## Parameters:
## - `statement_id`: Unique statement identifier for the policy.
## - `action`: Lambda action to allow (typically "lambda:InvokeFunction").
## - `function_name`: Name of the Lambda function to allow invocation.
## - `principal`: AWS service principal allowed to invoke the function (e.g., "apigateway.amazonaws.com").
## - `source_arn`: ARN of the API Gateway execution to restrict permission.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_lambda_permission" "this" {
  provider = aws.auth_session

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.aws_lambda_function.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_stage" "this" {
  provider = aws.auth_session

  stage_name    = var.api_stage
  description   = "${title(var.api_stage)} Stage for ${var.function_name} API"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id

  variables = {
    lambda_function_name = module.aws_lambda_function.lambda_function_name
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY DEPLOYMENT RESOURCE
##
## Deploy the API Gateway REST API to a specific stage, making changes live.
##
## Parameters:
## - `rest_api_id`: The ID of the REST API to deploy.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "this" {
  provider   = aws.auth_session
  depends_on = [aws_api_gateway_integration.this]

  rest_api_id = aws_api_gateway_rest_api.this.id
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY API KEY RESOURCE
##
## Create an API key for authenticating requests to the API Gateway.
##
## Parameters:
## - `name`: Name of the API key.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_api_key" "this" {
  provider = aws.auth_session

  name    = "${var.function_name}-${var.api_stage}-api-key"
  enabled = true
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY USAGE PLAN RESOURCE
##
## Create a usage plan to associate the API key with the API Gateway stage.
##
## Parameters:
## - `name`: Name of the usage plan.
## - `description`: Description of the usage plan.
## - `api_stages`: List of API stages to associate with the usage plan.
## - `throttle_settings`: Throttle settings for the usage plan, including burst limit and rate limit.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_usage_plan" "this" {
  provider = aws.auth_session

  name        = "${var.function_name}-${var.api_stage}-usage-plan"
  description = "${title(replace(var.function_name, "-", " "))} Usage Plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    burst_limit = 5
    rate_limit  = 10
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## AWS API GATEWAY USAGE PLAN KEY RESOURCE
##
## Associate the API key with the usage plan.
##
## Parameters:
## - `key_id`: The API key ID.
## - `key_type`: The type of key (must be "API_KEY").
## - `usage_plan_id`: The usage plan ID.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_api_gateway_usage_plan_key" "this" {
  provider = aws.auth_session

  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}
