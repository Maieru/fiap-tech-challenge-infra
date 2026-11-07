resource "aws_ecr_repository" "ecr-frontend-repository" {
  name                 = "fiap-ecr-frontend-repository"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}
