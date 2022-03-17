resource "random_integer" "default" {
  min     = 10001
  max     = 99999
}
resource "aws_s3_bucket" "default" {
  bucket = "${var.AWS_BUCKET_NAME}-${random_integer.default.result}"
}

resource "aws_acm_certificate" "default" {
  domain_name       = var.DOMAIN_NAME
  validation_method = "DNS"
}

resource "aws_route53_record" "default" {
  for_each = {
    for dvo in aws_acm_certificate.default.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.AWS_ROUTE53_ZONE_ID
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn         = aws_acm_certificate.default.arn
  validation_record_fqdns = [for record in aws_route53_record.default : record.fqdn]
}

data "aws_iam_policy_document" "default" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.default.iam_arn]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.default.arn,
      "${aws_s3_bucket.default.arn}/*",
    ]
  }
}
# {
#     "Version": "2008-10-17",
#     "Id": "PolicyForCloudFrontPrivateContent",
#     "Statement": [
#         {
#             "Sid": "1",
#             "Effect": "Allow",
#             "Principal": {
#                 "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E2THL19GA8XSI8"
#             },
#             "Action": "s3:GetObject",
#             "Resource": "arn:aws:s3:::office-staging.chateleon.com/*"
#         }
#     ]
# }

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.default.id
  policy = data.aws_iam_policy_document.default.json
}

resource "aws_cloudfront_origin_access_identity" "default" {
  comment = var.AWS_CLOUD_FRONT_OAI_COMMENT
}

resource "aws_cloudfront_distribution" "default" {
  origin {
    domain_name = aws_s3_bucket.default.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.default.bucket_regional_domain_name

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.DOMAIN_NAME]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["HEAD", "GET", "OPTIONS"]
    target_origin_id = aws_s3_bucket.default.bucket_regional_domain_name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"
  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 10
    response_code         = 200
    response_page_path    = "/index.html"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.default.arn
    ssl_support_method             = "sni-only"
    cloudfront_default_certificate = false
  }
}



resource "aws_route53_record" "default" {
  name    = var.DOMAIN_NAME
  type    = "A"
  zone_id = var.AWS_ROUTE53_ZONE_ID

  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.default.domain_name
    zone_id                = aws_cloudfront_distribution.default.hosted_zone_id
  }
}