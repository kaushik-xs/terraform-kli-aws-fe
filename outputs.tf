output "AWS_BUCKET_NAME" {
  value       = aws_s3_bucket.default.id
  description = "The bucket name where the UI assets will be stored"
}