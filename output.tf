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
  value       = aws_api_gateway_stage.this.invoke_url
}

output "api_gateway_key_id" {
  description = "API Gateway Key ID for usage with the API."
  value       = aws_api_gateway_api_key.this.id
}

output "api_gateway_key_value" {
  description = "API Gateway Key Value for usage with the API."
  value       = aws_api_gateway_api_key.this.value
  sensitive   = true
}
