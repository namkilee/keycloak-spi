data "terraform_remote_state" "bootstrap" {
    backend = "s3"
    config = {
        bucket                      = var.bootstrap_state_bucket
        key                         = var.bootstrap_state_key
        region                      = var.bootstrap_state_region
        endpoints                   = {
            s3 = var.bootstrap_state_endpoint
        }
        access_key                  = var.bootstrap_state_access_key
        secret_key                  = var.bootstrap_state_secret_key
        skip_credentials_validation = true
        skip_region_validation      = true
        skip_metadata_api_check     = true
        use_path_style              = true
        skip_requesting_account_id  = true
    }
}