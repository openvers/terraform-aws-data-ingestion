<p float="left">
  <img id="b-0" src="https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white" height="25px"/>
  <img id="b-1" src="https://img.shields.io/badge/Amazon_AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white" height="25px"/>
  <img id="b-2" src="https://img.shields.io/github/actions/workflow/status/sim-parables/terraform-aws-blob-trigger/tf-integration-test.yml?style=flat&logo=github&label=CD%20(October%202025)" height="25px"/>
</p>

---

# AWS Lambda HTTP Data Ingestion with API Gateway

This repository provides a Terraform-based solution for deploying a serverless data ingestion pipeline on AWS. The core components include:

- **AWS Lambda Function**: A Python-based Lambda function that ingests files via HTTP requests and writes them to an S3 bucket. The function expects a POST request with a file in the body and a filename in the query string or headers. The target S3 bucket is specified by the `TARGET_BUCKET` environment variable.

- **API Gateway**: An AWS API Gateway REST API exposes the Lambda function as an HTTP endpoint. API key authentication is enabled for secure access. Requests must include the `x-api-key` header with a valid API key.

- **S3 Buckets**: Used for storing ingested files and Lambda function artifacts.

- **Terraform Modules**: Modularized infrastructure for Lambda, API Gateway, S3, and supporting resources. Includes reusable modules for Lambda layers and SNS topics.

- **CI/CD & Testing**: GitHub Actions workflows for integration and unit testing, including local and OIDC-based test scenarios. Unit tests verify end-to-end ingestion by posting sample data to the API Gateway and checking S3 for the result.

## Key Features
- HTTP-triggered Lambda for file ingestion
- API Gateway with API key authentication
- Modular, reusable Terraform code
- Automated tests and GitHub Actions integration

## Usage
- Deploy with Terraform to provision all AWS resources
- Use the outputted API Gateway URL and API key to POST files for ingestion
- See the `test/unit_test/test_data_ingestion.py` for example usage and test automation

---


## Local Actions

Validate Github Workflows locally with [Nekto's Act](https://nektosact.com/introduction.html). More info found in the Github Repo [https://github.com/nektos/act](https://github.com/nektos/act).

### Prerequisits

Store the identical Secrets in Github Organization/Repository to local workstation

```bash
cat <<EOF > ~/creds/aws.secrets
# Terraform.io Token
TF_API_TOKEN=[COPY/PASTE MANUALLY]

# Github PAT
GITHUB_TOKEN=$(git auth token)

# AWS
AWS_REGION=$(aws configure get region)
AWS_OIDC_PROVIDER_ARN=[COPY/PASTE MANUALLY]
AWS_CLIENT_ID=[COPY/PASTE MANUALLY]
AWS_CLIENT_SECRET=[COPY/PASTE MANUALLY]
AWS_ROLE_TO_ASSUME=[COPY/PASTE MANUALLY]
AWS_ROLE_EXTERNAL_ID=[COPY/PASTE MANUALLY]
EOF
```

### Manual Dispatch Testing

```bash
# Try the Terraform Read job first
act -j terraform-dispatch-plan \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show)

act -j terraform-dispatch-apply \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show)

act -j terraform-dispatch-test \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show)

act -j terraform-dispatch-destroy \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show)
```

### Integration Testing

```bash
# Create an artifact location to upload/download between steps locally
mkdir /tmp/artifacts

# Run the full Integration test with
act -j terraform-integration-destroy \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show) \
    --artifact-server-path /tmp/artifacts
```

### Unit Testing

```bash
act -j terraform-unit-tests \
    -e .github/local.json \
    --secret-file ~/creds/aws.secrets \
    --remote-name $(git remote show)
```