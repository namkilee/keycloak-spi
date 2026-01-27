terraform {
  backend "s3" {
    bucket                      = "keycloak-terraform-state"
    key                         = "prd/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "https://minio.example.com"
    access_key                  = "minio"
    secret_key                  = "minio123"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
