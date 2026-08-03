variable "k8s_version" {
  description = <<-EOT
    Kubernetes version for the EKS cluster.

    The starter template pinned "1.25". AWS ended even extended support for EKS
    1.25 on 2025-05-01, so new 1.25 clusters can no longer be created and
    `terraform apply` fails with an unsupported-version error.

    1.33 is on standard EKS pricing ($0.10/hr). Versions that have fallen into
    "extended support" bill at $0.60/hr, which burns student credits 6x faster,
    so prefer a standard-support version here. If AWS has moved on by the time
    you run this, pick any currently supported version - the rest of the
    template does not care which one you use.
  EOT
  default     = "1.33"
}

variable "enable_private" {
  default = false
}

variable "public_az" {
  type        = string
  description = "Change this to a letter a-f only if you encounter an error during setup"
  default     = "a"
}

variable "private_az" {
  type        = string
  description = "Change this to a letter a-f only if you encounter an error during setup"
  default     = "b"
}
