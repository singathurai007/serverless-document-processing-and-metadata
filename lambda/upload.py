
import json
import boto3
import base64
import uuid

s3 = boto3.client("s3")

BUCKET_NAME = "serverless-document-api-399863053490"


def lambda_handler(event, context):

    try:
        body = json.loads(event["body"])

        file_name = body["file_name"]
        file_content = body["file_content"]

        file_data = base64.b64decode(file_content)

        object_key = f"uploads/{uuid.uuid4()}-{file_name}"

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=object_key,
            Body=file_data
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "File uploaded successfully",
                "file_name": file_name,
                "s3_key": object_key
            })
        }

    except Exception as e:

        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(e)
            })
        }
