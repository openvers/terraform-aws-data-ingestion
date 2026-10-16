output "service_account_client_id" {
  description = "AWS Service Account Client ID"
  value       = module.aws_service_account.access_id
  sensitive   = true
}

output "service_account_client_secret" {
  description = "AWS Service Account Client Secret"
  value       = module.aws_service_account.access_token
  sensitive   = true
}

output "assume_role" {
  description = "AWS IAM Assume Role with Web Identitiy Provider Name"
  value       = module.aws_identity_federation_roles.assume_role
}

output "assume_role_arn" {
  description = "AWS IAM Assume Role with Web Identitiy Provider Name"
  value       = module.aws_identity_federation_roles.assume_role_arn
}

output "lambda_function_arn" {
  description = "AWS Labda Function ARN"
  value       = module.aws_lambda_function.lambda_function_arn
}

output "lambda_function_iam_role_arn" {
  description = "AWS Lambda Function IAM Role ARN"
  value       = module.aws_lambda_function.lambda_function_iam_role_arn
}

output "lambda_function_assume_role_arn" {
  description = "AWS Lambda Function IAM Assume Role ARN"
  value       = module.aws_lambda_function.lambda_function_assume_role_arn
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the deployed API Gateway stage."
  value       = module.aws_lambda_function.api_gateway_invoke_url
}

output "bronze_bucket_id" {
  description = "Target S3 Bucket Name"
  value       = module.data_lake.bronze_bucket_id
}

output "api_gateway_key_id" {
  description = "API Gateway Key ID for usage with the API."
  value       = module.aws_lambda_function.api_gateway_key_id
}

output "api_gateway_key_value" {
  description = "API Gateway Key Value for usage with the API."
  value       = module.aws_lambda_function.api_gateway_key_value
  sensitive   = true
}