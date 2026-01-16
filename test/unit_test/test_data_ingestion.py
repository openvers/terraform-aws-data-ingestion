""" Unit Test: HTTP-triggered AWS Lambda File Upload

This unit test verifies the functionality of an AWS Lambda function triggered
by HTTP requests via API Gateway. The Lambda function is expected to receive a
file upload (in the HTTP request body) and a filename (as a query parameter or header),
and write the file to an S3 bucket specified by the TARGET_BUCKET environment variable.

The test sends a sample JSON payload to the Lambda's API Gateway endpoint and then
checks that the file has been correctly written to the S3 bucket. This ensures the
Lambda's HTTP integration and S3 write logic are functioning as intended.

Environment Variables Required:
 - TARGET_BUCKET: Name of the S3 bucket where files should be written.
 - API_GATEWAY_URL: The HTTP endpoint for the Lambda function (API Gateway invoke URL).
 - API_GATEWAY_KEY: API Gateway key for authentication.

References:
 - https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sts/client/assume_role_with_web_identity.html

Local Testing Steps:
```
terraform -chdir=./test init && \
terraform -chdir=./test apply -auto-approve

export TARGET_BUCKET=$(terraform -chdir=./test output -raw bronze_bucket_id)
export API_GATEWAY_URL=$(terraform -chdir=./test output -raw api_gateway_invoke_url)
export API_GATEWAY_KEY=$(terraform -chdir=./test output -raw api_gateway_key_value)

cd test/unit_test
python3 -m pytest -m 'local and env'

cd ../..
terraform -chdir=./test destroy -auto-approve
```
"""

import io
import json
import logging
import os
import time
import uuid

import boto3
import pytest
import requests
import s3fs

# Environment Variables
TARGET_BUCKET = os.getenv("TARGET_BUCKET")
API_GATEWAY_URL = os.getenv("API_GATEWAY_URL")
API_GATEWAY_KEY = os.getenv("API_GATEWAY_KEY")

assert TARGET_BUCKET is not None
assert API_GATEWAY_URL is not None
assert API_GATEWAY_KEY is not None


def _read_blob(filename, assume_role=None, oidc_token=None):
    """
    Reads a JSON file from the TARGET_BUCKET in S3.
    If assume_role and oidc_token are provided, uses STS to assume a role for access.

    Args:
        filename (str): The name of the file to read from S3.
        assume_role (str, optional): ARN of the role to assume for S3 access.
        oidc_token (str, optional): OIDC token for role assumption.

    Returns:
        dict: The JSON content of the file.
    """
    if assume_role and oidc_token:
        client = boto3.client("sts")
        creds = client.assume_role_with_web_identity(
            RoleArn=assume_role,
            RoleSessionName="github-unit-test-oidc-session",
            WebIdentityToken=oidc_token,
        )
        fs = s3fs.S3FileSystem(
            key=creds["Credentials"]["AccessKeyId"],
            secret=creds["Credentials"]["SecretAccessKey"],
            token=creds["Credentials"]["SessionToken"],
        )
    else:
        fs = s3fs.S3FileSystem()

    with fs.open(f"s3://{TARGET_BUCKET}/{filename}", "rb") as f:
        return json.loads(f.read())


@pytest.mark.local
@pytest.mark.env
def test_aws_env_http_lambda_file_upload(payload=None):
    """
    Test uploading a file to the Lambda via HTTP POST and verifying it is written to S3.
    Uses environment credentials for S3 access.

    Args:
        payload (dict, optional): The JSON payload to upload. If None, a random payload is generated.
    """
    logging.info("Pytest | Test HTTP Function File Upload with Environment Credentials")
    if payload is None:
        payload = {"test_value": str(uuid.uuid4())}
    filename = f"test-env-{str(uuid.uuid4())}.json"

    # Send HTTP POST to Lambda via API Gateway
    response = requests.post(
        url=f"{API_GATEWAY_URL}/api/upload",
        headers={"x-api-key": API_GATEWAY_KEY},
        files=[("files", (filename, io.BytesIO(json.dumps(payload).encode("utf-8"))))],
    )

    assert response.status_code == 200, f"Lambda HTTP call failed: {response.text}"

    # Verify the file was written to S3
    rs = _read_blob(filename)
    assert rs["test_value"] == payload["test_value"]


@pytest.mark.github
@pytest.mark.oidc
def test_aws_oidc_http_lambda_file_upload(payload=None):
    """
    Test uploading a file to the Lambda via HTTP POST and verifying it is written to S3.
    Uses OIDC and role assumption for S3 access.

    Args:
        payload (dict, optional): The JSON payload to upload. If None, a random payload is generated.
    """
    logging.info("Pytest | Test HTTP Lambda File Upload")
    ASSUME_ROLE = os.getenv("ASSUME_ROLE")
    OIDC_TOKEN = os.getenv("OIDC_TOKEN")
    assert not ASSUME_ROLE is None
    assert not OIDC_TOKEN is None

    if payload is None:
        payload = {"test_value": str(uuid.uuid4())}
    filename = "test.json"

    # Send HTTP POST to Lambda via API Gateway
    response = requests.post(
        API_GATEWAY_URL,
        params={"filename": filename},
        data=json.dumps(payload),
        headers={"Content-Type": "application/json", "x-api-key": API_GATEWAY_KEY},
    )

    assert response.status_code == 200, f"Lambda HTTP call failed: {response.text}"

    # Wait for the Lambda to write to S3
    time.sleep(5)

    # Verify the file was written to S3
    rs = _read_blob(filename, assume_role=ASSUME_ROLE, oidc_token=OIDC_TOKEN)
    assert rs["test_value"] == payload["test_value"]
