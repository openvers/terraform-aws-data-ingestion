<p float="left">
  <img id="b-0" src="https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white" height="25px"/>
  <img id="b-1" src="https://img.shields.io/badge/Amazon_AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white" height="25px"/>
  <img id="b-2" src="https://img.shields.io/github/actions/workflow/status/openvers/terraform-aws-data-ingestion/tf-integration-test.yml?style=flat&logo=github&label=CD" height="25px"/>
</p>

# Terraform AWS Data Ingestion Module

## Overview

This repository provides a modular Terraform implementation for provisioning a serverless HTTP data ingestion pipeline on AWS. It includes:
- A Python Lambda application exposed through an API Gateway REST API
- API key requirements and usage-plan throttling
- S3 storage for Lambda source artifacts and access to existing ingestion buckets
- Lambda dependency layers, IAM permissions, KMS integration, and CloudWatch logging
- A reusable SNS topic module for Lambda dead-letter handling

## Module Structure

- `modules/aws_lambda_python_app/` – Python Lambda packaging, source artifact bucket, Lambda Web Adapter integration, IAM permissions, and logging
- `modules/aws_functions_layers/` – Python dependency packaging and Lambda layer creation
- `modules/aws_sns_topic/` – SNS topic creation with KMS encryption configuration

---

## Usage

The following example uses the bundled Flask application. Replace the bucket names and ARNs with existing resources, and set `source` to this module's location. Artifact bucket names must be globally unique.

```hcl
provider "aws" {
  alias  = "auth_session"
  region = "us-east-1"
}

module "data_ingestion" {
  source = "../terraform-aws-data-ingestion"

  function_name        = "my-data-ingestion"
  function_handler     = "run.sh"
  function_bucket_name = "my-unique-ingestion-artifacts"
  bucket_ids           = ["my-bronze-bucket"]
  kms_key_arn          = "arn:aws:kms:us-east-1:123456789012:key/your-key-id"
  sns_topic_arn        = "arn:aws:sns:us-east-1:123456789012:my-dead-letter-topic"

  function_contents = [
    for filename in ["main.py", "requirements.txt", "run.sh"] : {
      filename = filename
      filepath = "${path.module}/../terraform-aws-data-ingestion/test/source/${filename}"
    }
  ]

  function_dependencies = {
    application = [
      {
        package_name    = "flask"
        package_version = "3.1.2"
        no_dependencies = false
      },
      {
        package_name    = "gunicorn"
        package_version = "23.0.0"
        no_dependencies = false
      },
      {
        package_name    = "s3fs"
        package_version = "2025.12.0"
        no_dependencies = false
      }
    ]
  }

  function_environment_variables = {
    TARGET_BUCKET = "my-bronze-bucket"
  }

  providers = {
    aws.auth_session = aws.auth_session
  }
}
```

See [`variables.tf`](./variables.tf) for module inputs and [`output.tf`](./output.tf) for outputs, including `api_gateway_invoke_url` and the sensitive `api_gateway_key_value`. A complete deployment combining the ingestion module, data lake, and SNS topic is provided in [`test/main.tf`](./test/main.tf).

After deploying the test harness below, upload a file using its outputs:

```bash
export API_GATEWAY_URL="$(terraform -chdir=test output -raw api_gateway_invoke_url)"
export API_GATEWAY_KEY="$(terraform -chdir=test output -raw api_gateway_key_value)"

curl --fail-with-body \
  --header "x-api-key: ${API_GATEWAY_KEY}" \
  --form "files=@./test/source/requirements.txt" \
  "${API_GATEWAY_URL}/api/upload"
```

The application uses the uploaded filename, sanitized with `secure_filename`, as the S3 object key. Multiple files can be sent by repeating the `files` form field.

## Testing

A test harness is provided in the [`test/`](./test/) directory. It includes:
- Service account and GitHub Actions OIDC federation setup
- Bronze, Silver, and Gold buckets and a KMS key through the Data Lake module
- An SNS topic, the sample Lambda application, and API Gateway deployment
- Terraform outputs for local tests and CI/CD pipelines
- Pytest checks that upload sample data over HTTP and verify the resulting S3 object

Validate GitHub workflows locally with [Nektos Act](https://nektosact.com/introduction.html). More information is available in the [Act repository](https://github.com/nektos/act).

### Prerequisites

```bash

# [TODO] Remainig Under Construction (AWS portal steps/ equiv. CLI commands)
# [TODO] Add the AWSReservedSSO_AdministratorAccess to the Assume Role supplied in <service-principal-arn>

cat << 'EOF' > ~/creds/aws.secrets.envrc
SERVICE_PRINCIPAL_ROLE_ARN="<service-principal-arn>"

AWS_CREDS=$(
  aws sts assume-role \
    --role-arn "${SERVICE_PRINCIPAL_ROLE_ARN}" \
    --role-session-name "terraform-developer-session"
)

export AWS_CLIENT_ID=$(echo $AWS_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_CLIENT_SECRET=$(echo $AWS_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $AWS_CREDS | jq -r '.Credentials.SessionToken')

export AWS_OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[0].Arn' --output text)
export TF_VAR_OIDC_PROVIDER_ARN=$AWS_OIDC_PROVIDER_ARN

export TF_API_TOKEN=$(cat ~/.terraform.d/credentials.tfrc.json | jq -r '.credentials."app.terraform.io".token')
EOF
```

### Local Deployment Testing

```bash
aws sso login
terraform login app.terraform.io

terraform -chdir=test init
terraform -chdir=test plan
terraform -chdir=test apply -auto-approve

export TARGET_BUCKET="$(terraform -chdir=test output -raw bronze_bucket_id)"
export API_GATEWAY_URL="$(terraform -chdir=test output -raw api_gateway_invoke_url)"
export API_GATEWAY_KEY="$(terraform -chdir=test output -raw api_gateway_key_value)"

python3 -m pytest test/unit_test -m "local and env" -rs

terraform -chdir=test destroy -auto-approve
```

### Manual Dispatch Testing

```bash
# Try the Terraform plan job first
act -j terraform-dispatch-plan \
  -e .github/local.json \
  -s AWS_CLIENT_ID \
  -s AWS_CLIENT_SECRET \
  -s AWS_SESSION_TOKEN \
  -s AWS_REGION \
  -s AWS_OIDC_PROVIDER_ARN \
  -s TF_VAR_OIDC_PROVIDER_ARN \
  -s TF_API_TOKEN \
  --remote-name origin

act -j terraform-dispatch-apply \
  -e .github/local.json \
  -s AWS_CLIENT_ID \
  -s AWS_CLIENT_SECRET \
  -s AWS_SESSION_TOKEN \
  -s AWS_REGION \
  -s AWS_OIDC_PROVIDER_ARN \
  -s TF_VAR_OIDC_PROVIDER_ARN \
  -s TF_API_TOKEN \
  --remote-name origin

act -j terraform-dispatch-test \
  -e .github/local.json \
  -s AWS_CLIENT_ID \
  -s AWS_CLIENT_SECRET \
  -s AWS_SESSION_TOKEN \
  -s AWS_REGION \
  -s AWS_OIDC_PROVIDER_ARN \
  -s TF_VAR_OIDC_PROVIDER_ARN \
  -s TF_API_TOKEN \
  --remote-name origin

act -j terraform-dispatch-destroy \
  -e .github/local.json \
  -s AWS_CLIENT_ID \
  -s AWS_CLIENT_SECRET \
  -s AWS_SESSION_TOKEN \
  -s AWS_REGION \
  -s AWS_OIDC_PROVIDER_ARN \
  -s TF_VAR_OIDC_PROVIDER_ARN \
  -s TF_API_TOKEN \
  --remote-name origin
```

### Integration Testing

```bash
# Create an artifact location for local workflow uploads/downloads
mkdir -p /tmp/artifacts

act -j terraform-integration-destroy \
  -e .github/local.json \
  -s AWS_CLIENT_ID \
  -s AWS_CLIENT_SECRET \
  -s AWS_SESSION_TOKEN \
  -s AWS_REGION \
  -s AWS_OIDC_PROVIDER_ARN \
  -s TF_VAR_OIDC_PROVIDER_ARN \
  -s TF_API_TOKEN \
  --remote-name origin \
  --artifact-server-path /tmp/artifacts
```

### Unit Testing

Run the Terraform unit-test workflow independently:

```bash
act -j terraform-unit-tests \
  -e .github/local.json \
  --secret-file ~/creds/aws.secrets \
  --remote-name origin
```

---

## License

See [LICENSE](./LICENSE) for details.
