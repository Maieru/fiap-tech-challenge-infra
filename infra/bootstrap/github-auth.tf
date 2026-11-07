resource "aws_iam_openid_connect_provider" "oicd-github-actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
data "aws_caller_identity" "current" {}
