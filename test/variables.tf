## ---------------------------------------------------------------------------------------------------------------------
## MODULE PARAMETERS
## These variables are expected to be passed in by the operator
## ---------------------------------------------------------------------------------------------------------------------

variable "service_account_name" {
  type        = string
  description = "New AWS Service Account to be Created"
}

variable "service_account_path" {
  type        = string
  description = "New AWS Service Account Path"
}

variable "OIDC_PROVIDER_ARN" {
  type        = string
  description = "Existing AWS IAM OpenID Connect Provider ARN"
}

## ---------------------------------------------------------------------------------------------------------------------
## OPTIONAL PARAMETERS
## These variables have defaults and may be overridden
## ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS Provider Region"
  default     = "us-east-1"
}

variable "GITHUB_REPOSITORY_OWNER" {
  type        = string
  description = "Github Actions Default ENV Variable for the Repo Owner"
  default     = "openverse"
}

variable "GITHUB_REPOSITORY" {
  type        = string
  description = "Github Actions Default ENV Variable for the Repo Path"
  default     = "openverse/terraform-aws-service-account"
}

variable "GITHUB_REF" {
  type        = string
  description = "Github Actions Default ENV Variable for full form of the Branch or Tag"
  default     = null
}

variable "GITHUB_ENV" {
  type        = string
  description = <<EOT
    Github Environment in which the Action Workflow's Job or Step is running. Ex: production.
    This is not found in Github Action's Default Environment Variables and will need to be
    defined manually.
  EOT
  default     = null
}
