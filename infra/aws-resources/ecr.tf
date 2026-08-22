resource "aws_ecr_repository" "ecr-backend-repository" {
  name                 = "fiap-ecr-backend-repository"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "*latest"
    filter_type = "WILDCARD"
  }
  force_delete = true
}

resource "aws_ecr_repository" "ecr-frontend-repository" {
  name                 = "fiap-ecr-frontend-repository"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "*latest"
    filter_type = "WILDCARD"
  }
  force_delete = true
}
