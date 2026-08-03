####################
# VPC Configuration
####################
# Create a VPC
resource "aws_vpc" "vpc" {
  tags = {
    "Name" = "udacity"
  }
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1${var.public_az}"
  map_public_ip_on_launch = true
  tags = {
    Name = "udacity-public"
  }
}

# Create public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

# Associate the route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

# Create a private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "us-east-1${var.private_az}"
  cidr_block        = "10.0.2.0/24"
  tags = {
    Name = "udacity-private"
  }
}

# Create private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "private"
  }
}

# Associate private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}

# Create EKS endpoint for private access
resource "aws_vpc_endpoint" "eks" {
  count               = var.enable_private == true ? 1 : 0 # only enable when private
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.eks"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_eks_cluster.main.vpc_config.0.cluster_security_group_id]
  subnet_ids          = [aws_subnet.private_subnet.id]
  private_dns_enabled = true
}

# Create EC2 endpoint for private access
resource "aws_vpc_endpoint" "ec2" {
  count               = var.enable_private == true ? 1 : 0
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ec2"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_eks_cluster.main.vpc_config.0.cluster_security_group_id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr-dkr-endpoint" {
  count               = var.enable_private == true ? 1 : 0
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_eks_cluster.main.vpc_config.0.cluster_security_group_id]
  subnet_ids          = [aws_subnet.private_subnet.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr-api-endpoint" {
  count               = var.enable_private == true ? 1 : 0
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_eks_cluster.main.vpc_config.0.cluster_security_group_id]
  subnet_ids          = [aws_subnet.private_subnet.id]
  private_dns_enabled = true
}

###################
# ECR Repositories
###################
resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

################
# EKS Resources
################
# Create an EKS cluster
resource "aws_eks_cluster" "main" {
  name     = "cluster"
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster.arn
  vpc_config {
    subnet_ids              = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]
    endpoint_public_access  = var.enable_private == true ? false : true
    endpoint_private_access = true
  }

  # API_AND_CONFIG_MAP keeps the legacy aws-auth ConfigMap working (so
  # setup/init.sh still does what the course README says) while also enabling
  # EKS Access Entries, which is what the two resources below use.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster, aws_iam_role_policy_attachment.eks_service]
}

# Grant the GitHub Actions IAM user admin access to the cluster.
#
# The course tells you to do this by hand with setup/init.sh, which downloads a
# linux/amd64 `aws-iam-authenticator` binary and patches the aws-auth ConfigMap.
# That script cannot run on macOS or Apple Silicon. Declaring the access entry
# here does the same job, from any machine, and it is tracked in state so it
# survives a cluster rebuild. You do NOT need to run init.sh if you use this.
resource "aws_eks_access_entry" "github_action_user" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_user.github_action_user.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_action_user_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_user.github_action_user.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_action_user]
}


# Create an IAM role for the EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks_cluster_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the EKS cluster IAM role
resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_service" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}


##################
# EKS Node Group
##################
# NOTE: the original template pinned an explicit `release_version` looked up from
# the SSM path /aws/service/eks/optimized-ami/<version>/amazon-linux-2/...
# Amazon Linux 2 EKS AMIs stopped being published after Kubernetes 1.32, so that
# lookup now 404s. Omitting `release_version` entirely lets EKS pick its own
# recommended AMI for the cluster version, which is both simpler and durable.
resource "aws_eks_node_group" "main" {
  node_group_name = "udacity"
  cluster_name    = aws_eks_cluster.main.name
  version         = aws_eks_cluster.main.version
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = [var.enable_private == true ? aws_subnet.private_subnet.id : aws_subnet.public_subnet.id]
  # AL2023 is the current EKS node OS. The provider default is still AL2_x86_64,
  # which is not available on Kubernetes >= 1.33.
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }


  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node_group_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config.0.desired_size]
  }
}

// IAM Configuration
resource "aws_iam_role" "node_group" {
  name               = "udacity-node-group"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "node_group_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

######################
# CodeBuild Resources
######################
# REMOVED. The starter template created an aws_codebuild_project whose source was
# a GITHUB repo at the placeholder URL https://github.com/your-org/your-repo.
# CreateProject with a GITHUB source requires an OAuth/PAT connection on the
# account, so this resource fails `terraform apply` with:
#   "No Access token found, please visit AWS CodeBuild console to connect to GITHUB"
# Nothing in this project uses CodeBuild - CI/CD runs entirely in GitHub Actions -
# so the project and its IAM role have been dropped rather than worked around.

####################
# Github Action role
####################
resource "aws_iam_user" "github_action_user" {
  name = "github-action-user"
}

# NOTE: the original template used an *inline* user policy (aws_iam_user_policy,
# i.e. the iam:PutUserPolicy API). AWS Academy / Udacity "voclabs" federated
# roles deny iam:PutUserPolicy, so that resource fails with:
#   AccessDenied: ... not authorized to perform: iam:PutUserPolicy
# The same role IS allowed iam:CreatePolicy and iam:AttachUserPolicy, so this
# grants the identical permissions as a customer-managed policy attachment
# instead. Functionally equivalent, and it applies cleanly as the lab user.
resource "aws_iam_policy" "github_action_user_permission" {
  name        = "github-action-user-policy"
  description = "Permissions for the GitHub Actions CI/CD user (ECR push, EKS describe)"
  policy      = data.aws_iam_policy_document.github_policy.json
}

resource "aws_iam_user_policy_attachment" "github_action_user_permission" {
  user       = aws_iam_user.github_action_user.name
  policy_arn = aws_iam_policy.github_action_user_permission.arn
}

data "aws_iam_policy_document" "github_policy" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:*", "eks:*", "ec2:*", "iam:GetUser"]
    resources = ["*"]
  }
}
