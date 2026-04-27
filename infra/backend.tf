# Fill in your backend values after running infra/bootstrap/.
# The bootstrap module outputs a ready-made backend_block — copy it here.
#
# terraform {
#   backend "s3" {
#     bucket         = "<output from bootstrap: bucket_name>"
#     key            = "<project>/<environment>/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "<output from bootstrap: dynamodb_table_name>"
#     encrypt        = true
#   }
# }
