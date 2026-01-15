
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "plugin_bucket" {
  count  = var.create_connectors ? 1 : 0
  bucket = var.plugin_bucket_name != "" ? var.plugin_bucket_name : "msk-connector-plugins-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags = { Name = "msk-connector-plugins" }
}

resource "aws_s3_object" "debezium_plugin" {
  count   = var.create_connectors && length(var.debezium_plugin_local_path) > 0 ? 1 : 0
  bucket  = aws_s3_bucket.plugin_bucket[0].id
  key     = var.debezium_plugin_key
  source  = var.debezium_plugin_local_path
  content_type = "application/zip"
}

resource "aws_s3_object" "jdbc_plugin" {
  count   = var.create_connectors && length(var.jdbc_plugin_local_path) > 0 ? 1 : 0
  bucket  = aws_s3_bucket.plugin_bucket[0].id
  key     = var.jdbc_plugin_key
  source  = var.jdbc_plugin_local_path
  content_type = "application/zip"
}

resource "aws_mskconnect_custom_plugin" "debezium" {
  count = var.create_connectors && var.debezium_plugin_local_path != "" ? 1 : 0
  name = var.debezium_plugin_name
  description = "Debezium connector plugin"
  location {
    s3 {
      bucket_arn = aws_s3_bucket.plugin_bucket[0].arn
      file_key   = var.debezium_plugin_key
    }
  }
  content_type = "ZIP"
}

resource "aws_mskconnect_custom_plugin" "jdbc" {
  count = var.create_connectors && var.jdbc_plugin_local_path != "" ? 1 : 0
  name = var.jdbc_plugin_name
  description = "JDBC sink connector plugin"
  location {
    s3 {
      bucket_arn = aws_s3_bucket.plugin_bucket[0].arn
      file_key   = var.jdbc_plugin_key
    }
  }
  content_type = "ZIP"
}

/* MSK Connect connector resources intentionally removed to allow plan/apply to create
   S3 bucket and custom plugins independently. Create connectors manually via CLI
   or re-add resources after generating connector JSONs (connectors/generated/).
*/
