variable "region" {
  default     = "eu-west-3"
  description = "AWS Region"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

##------- Lamdba ressource -------
resource "aws_lambda_function" "lambda-poc" {
  function_name = "api-gw-lamba-poc"

  architectures = ["arm64"]
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

##------- CloudWatch looging config -------

resource "aws_cloudwatch_log_group" "lambda_poc_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda-poc.function_name}"
  retention_in_days = 14
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
  name               = "iam-for-lambda-poc"
  assume_role_policy = data.aws_iam_policy_document.lambda_iam_assume_role_policy.json
}

resource "aws_iam_policy" "lambda_logging" {
  name   = "lambda-logging-policy"
  policy = data.aws_iam_policy_document.lambda_logging_policy.json
}

data "aws_iam_policy_document" "lambda_logging_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.lambda-poc.function_name}:*"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

##------- Api Gateway config -------

resource "aws_apigatewayv2_api" "poc_api" {
  name          = "poc_api"
  protocol_type = "HTTP"
}

# These 3 are necessary for each lambda to be related to the api_gateway, so it can be generalized as a module
resource "aws_apigatewayv2_integration" "lambda_integration" { # the technical and logical connection between the Route and one ressource (invoke)
  api_id              = aws_apigatewayv2_api.poc_api.id
  integration_type    = "AWS_PROXY"
  integration_uri     = aws_lambda_function.lambda-poc.invoke_arn # It is important to note that for an API to invoke a function, Lambda requires its execution ARN, not the resource ARN.
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" { # a combination of the HTTP method with the API route (endpoint path) + integration. Routes can optionally use Authorizers.
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

# configuration for deployments, throttling options can be added here and they'll change according to the stage
resource "aws_apigatewayv2_stage" "test" {
  api_id = aws_apigatewayv2_api.poc_api.id
  name   = "test"
  auto_deploy = true
}