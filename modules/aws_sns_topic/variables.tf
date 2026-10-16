## ---------------------------------------------------------------------------------------------------------------------
## MODULE PARAMETERS
## These variables are expected to be passed in by the operator
## ---------------------------------------------------------------------------------------------------------------------

variable "sns_topic_name" {
  type        = string
  description = "AWS Simple Notification Service Topic Name"
}

variable "kms_key_id" {
  type        = string
  description = "KMS Encryption Key ID"
}

## ---------------------------------------------------------------------------------------------------------------------
## OPTIONAL PARAMETERS
## These variables have defaults and may be overridden
## ---------------------------------------------------------------------------------------------------------------------

