provider "aws" {
  region = "eu-west-3"
}

data "aws_iam_policy_document" "lambda_iam_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam-for-lambda-poc"
  assume_role_policy = data.aws_iam_policy_document.lambda_iam_assume_role_policy.json
}

resource "aws_lambda_function" "lambda-poc" {
  function_name = "api-gw-lamba-poc"

  s3_bucket = "jojo-lambda-poc"
  s3_key    = "lambda.poc.zip"
  handler   = "src/index.handler"
  runtime   = "nodejs20.x"

  role      = "${aws_iam_role.iam_for_lambda.arn}"
  environment {
    variables = {
      NODE_ENV = "test"
    }
  }
}

#manque cloudwatch pour le logs (ou équivalent)

resource "aws_apigatewayv2_api" "poc_api" {
  name          = "poc_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id              = aws_apigatewayv2_api.poc_api.id
  integration_type    = "AWS_PROXY"
  integration_uri     = aws_lambda_function.lambda-poc.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.poc_api.id
  route_key = "POST /poc"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda-poc.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.poc_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "test" {
  api_id = aws_apigatewayv2_api.poc_api.id
  name   = "test"
  auto_deploy = true
}