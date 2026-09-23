terraform{
  required_providers{
      aws ={
         source="hashicorp/aws"
         version = "~>6.0"
        }
      }

      required_version = ">=1.6.0"
}

provider "aws"{
     region ="ap-south-1"
}

resource "aws_s3_bucket" "d0cuments"{
         bucket ="serverless-document-api-399863053490"
       }

   
resource "aws_dynamodb_table" "metadata"{
  name = "document-metadata"
  billing_mode="PAY_PER_REQUEST"
  hash_key ="document_id"

  attribute{
     name="document_id"
     type = "S"
    }
}

resource "aws_iam_role" "lambda_upload_role"{
   name="serverless-document-upload-lambda-role"

   assume_role_policy =jsonencode({
     Version ="2012-10-17"

     Statement =[
      {
       Effect ="Allow"
       
       Principal={
          Service ="lambda.amazonaws.com"
         }

         Action = "sts:AssumeRole"
       }
      ]
     })
}
        
resource "aws_iam_role_policy" "lambda_upload_policy" {
  name = "serverless-document-upload-policy"
  role = aws_iam_role.lambda_upload_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:PutObject"
        ]

        Resource = "arn:aws:s3:::serverless-document-api-399863053490/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


data "archive_file" "upload_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/upload.py"
  output_path = "${path.module}/upload.zip"
}

resource "aws_lambda_function" "upload" {
  function_name = "serverless-document-upload"

  filename         = data.archive_file.upload_lambda_zip.output_path
  source_code_hash = data.archive_file.upload_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_upload_role.arn

  handler = "upload.lambda_handler"
  runtime = "python3.13"

  timeout = 30
}


resource "aws_apigatewayv2_api" "upload_api"{
   name ="serverless-document-api"
   protocol_type ="HTTP"
}

resource "aws_apigatewayv2_integration" "upload_lambda" {
  api_id = aws_apigatewayv2_api.upload_api.id

  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.upload.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.upload_api.id
  route_key = "POST /upload"

  target = "integrations/${aws_apigatewayv2_integration.upload_lambda.id}"
}


resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.upload_api.id

  name = "$default"

  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload.function_name
  principal     = "apigateway.amazonaws.com"
}


resource "aws_iam_role" "metadata_lambda_role" {
  name = "serverless-document-metadata-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "metadata_lambda_policy" {
  name = "serverless-document-metadata-policy"

  role = aws_iam_role.metadata_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:HeadObject",
          "s3:GetObject"
        ]

        Resource = "arn:aws:s3:::serverless-document-api-399863053490/*"
      },
      {
        Effect = "Allow"

        Action = [
          "dynamodb:PutItem"
        ]

        Resource = "arn:aws:dynamodb:ap-south-1:399863053490:table/document-metadata"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "metadata_lambda_basic_execution" {
  role       = aws_iam_role.metadata_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "metadata_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/metadata.py"
  output_path = "${path.module}/metadata.zip"
}

resource "aws_lambda_function" "metadata" {
  function_name = "serverless-document-metadata"

  filename         = data.archive_file.metadata_lambda_zip.output_path
  source_code_hash = data.archive_file.metadata_lambda_zip.output_base64sha256

  role = aws_iam_role.metadata_lambda_role.arn

  handler = "metadata.lambda_handler"
  runtime = "python3.13"

  timeout = 30
}

resource "aws_lambda_permission" "s3_metadata" {
  statement_id  = "AllowS3InvokeMetadataLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metadata.function_name
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.d0cuments.arn
}


resource "aws_s3_bucket_notification" "documents" {
  bucket = aws_s3_bucket.d0cuments.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.metadata.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.s3_metadata
  ]
}
