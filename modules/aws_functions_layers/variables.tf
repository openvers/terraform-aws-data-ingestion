## ---------------------------------------------------------------------------------------------------------------------
## MODULE PARAMETERS
## These variables are expected to be passed in by the operator
## ---------------------------------------------------------------------------------------------------------------------

variable "layer_name" {
  type        = string
  description = "Name of the Lambda Layer"
}

variable "layer_packages" {
  type = list(object({
    package_name    = string
    package_version = string
    no_dependencies = bool
  }))
  description = "Python Dependency Packages Required for Lambda Layer"
}

variable "bucket_id" {
  type        = string
  description = "AWS Storage Bucket ID for Lambda Source Code"
}

## ---------------------------------------------------------------------------------------------------------------------
## OPTIONAL PARAMETERS
## These variables have defaults and may be overridden
## ---------------------------------------------------------------------------------------------------------------------

variable "function_runtime" {
  type        = string
  description = "AWS Lambda Function Runtime Environment"
  default     = "python3.12"
}
