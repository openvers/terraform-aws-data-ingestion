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
## AWS SNS TOPIC RESOURCCE
## 
## Create an AWS Simple Notification Services Topic to share with downstream resources.
##
## Parameters:
## - `name`: AWS SNS Topic name.
## - `kms_master_key_id`: KMS key ID to encrypt messages at rest.
## ---------------------------------------------------------------------------------------------------------------------
resource "aws_sns_topic" "this" {
  provider = aws.auth_session

  name              = var.sns_topic_name
  kms_master_key_id = var.kms_key_id
}
