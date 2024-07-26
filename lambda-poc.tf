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
  #environment {
  #  variables = {
  #    foo = "bar"
  #  }
  #}
}

#manque cloudwatch pour le logs (ou équivalent)

resource "aws_api_gateway_rest_api" "automatic-poc" {
  name        = "ApiGatewayAutomatique"
  description = "POC"
}

resource "aws_api_gateway_resource" "automatic-poc-proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.automatic-poc.id}"
  parent_id   = "${aws_api_gateway_rest_api.automatic-poc.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy-method-for-poc" {
  rest_api_id   = "${aws_api_gateway_rest_api.automatic-poc.id}"
  resource_id   = "${aws_api_gateway_resource.automatic-poc-proxy.id}"
  http_method   = "POST"
  authorization = "NONE"
}

# config to link the api gateway with the lamba
resource "aws_api_gateway_integration" "lambda-integration" {
  rest_api_id = "${aws_api_gateway_rest_api.automatic-poc.id}"
  resource_id = "${aws_api_gateway_method.proxy-method-for-poc.resource_id}"
  http_method = "${aws_api_gateway_method.proxy-method-for-poc.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda-poc.invoke_arn}"
}

# root
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.automatic-poc.id}"
  resource_id   = "${aws_api_gateway_rest_api.automatic-poc.root_resource_id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.automatic-poc.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda-poc.invoke_arn}"
}

resource "aws_api_gateway_deployment" "lambda-poc" {
  depends_on = [
    "aws_api_gateway_integration.lambda-integration",
    "aws_api_gateway_integration.lambda_root_integration",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.automatic-poc.id}"
  stage_name  = "test"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda-poc.function_name}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_rest_api.automatic-poc.execution_arn}/*/*"
}