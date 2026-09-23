import json
import boto3
from datetime import datetime, timezone
from urllib.parse import unquote_plus

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = "document-metadata"


def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        response = s3.head_object(
            Bucket=bucket,
            Key=key
        )

        document_id = key.split("/")[-1]

        item = {
            "document_id": document_id,
            "file_name": document_id,
            "file_size": response["ContentLength"],
            "upload_time": datetime.now(timezone.utc).isoformat(),
            "s3_bucket": bucket,
            "s3_key": key
        }

        table.put_item(Item=item)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Metadata saved successfully"
        })
    }
