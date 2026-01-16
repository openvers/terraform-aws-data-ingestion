"""AWS Lambda Functions Application Example

An AWS Lambda Function is a serverless function that automatically executes in response to events.
This function will write the contents of HTTP request into file of the
OUTPUT Blob Store given the filename passed into HTTP request parameter "name".
This trigger mechanism  enables event-driven architecture and allows you to build
scalable and event-based solutions on Azure.

"""

import logging
import os
import sys

import s3fs
from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename

# Environment Variables
TARGET_BUCKET = os.getenv("TARGET_BUCKET")

# Setup
logging.basicConfig(stream=sys.stdout, level=logging.INFO)
flask_app = Flask(__name__)


@flask_app.route("/api/upload", methods=["POST"])
def run():
    try:
        logging.info("HTTP Request Received")
        if "files" not in request.files:
            return jsonify({"error": "No file part"}), 400

        fs = s3fs.S3FileSystem()
        for file in request.files.getlist("files"):
            logging.info(
                f"HTTP Request: {secure_filename(file.filename)} | Initiating Data Ingestion"
            )
            with fs.open(
                os.path.join(f"s3://{TARGET_BUCKET}", secure_filename(file.filename)),
                "wb",
            ) as f:
                file.save(f)

        return "Data Ingestion Succesfull", 200

    except Exception as e:
        logging.error(f"Error: {e}")
        return "Data Ingestion Failed", 500
