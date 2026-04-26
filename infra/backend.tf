# Populate after running infra/bootstrap. The `bucket` value from
# bootstrap's `bucket_name` output goes in the `bucket` field.
#
# terraform {
#   backend "s3" {
#     bucket         = "alexanderkachar-tfstate-<suffix>"
#     key            = "private-eks/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "alexanderkachar-tf-locks"
#     encrypt        = true
#   }
# }
