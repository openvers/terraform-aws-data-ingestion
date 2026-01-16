output "lambda_function_name" {
  description = "AWS Lambda Function Name"
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "AWS Labda Function ARN"
  value       = aws_lambda_function.this.arn
}

output "lambda_function_iam_role_arn" {
  description = "AWS Lambda Function IAM Role ARN"
  value       = aws_iam_role.this.arn
}

output "lambda_function_assume_role_arn" {
  description = "AWS Lambda Function IAM Assume Role ARN"
  value       = "arn:aws:sts::${split(":", aws_iam_role.this.arn)[4]}:assumed-role/${var.function_name}-role/${var.function_name}"
}

output "lambda_function_invoke_arn" {
  description = "AWS Lambda Function Invoke ARN"
  value       = aws_lambda_function.this.invoke_arn
}

output "cloudwatch_log_group_name" {
  description = "AWS Lambda Function CloudWatch Log Group Name"
  value       = aws_cloudwatch_log_group.this.name
}