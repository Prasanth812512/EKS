variable "instance_type" {}
variable "tag_name" {}
variable "public_key" {}
variable "subnet_id" {}
variable "sg_for_jenkins" {}  # Corrected variable name
variable "enable_public_ip_address" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {}

output "ssh_connection_string_for_ec2" {
  value = format("%s%s", "ssh -i /Users/rahulwagh/.ssh/aws_ec2_terraform ubuntu@", aws_instance.kubectl-server.private_ip)
}

output "jenkins_ec2_instance_ip" {
  value = aws_instance.kubectl-server.id
}

output "dev_proj_1_ec2_instance_public_ip" {
  value = aws_instance.kubectl-server.public_ip
}

data "aws_ami" "latest" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_instance" "kubectl-server" {
  ami                          = data.aws_ami.latest.id
  instance_type                = var.instance_type
  tags                         = {
    Name = var.tag_name
  }
  key_name                     = "keys"
  subnet_id                    = var.subnet_id
  vpc_security_group_ids       = var.sg_for_jenkins  # Corrected variable name
  associate_public_ip_address  = var.enable_public_ip_address

  provisioner "remote-exec" {
    inline = [
      "curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl",
      "chmod +x ./kubectl",
      "mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH",
      "sudo snap install aws-cli --classic",
      "aws configure set aws_access_key_id ${var.aws_access_key}",
      "aws configure set aws_secret_access_key ${var.aws_secret_key}",
      "aws configure set default.region ${var.aws_region}",
      "aws configure set default.output json",
      "aws eks update-kubeconfig --region ${var.aws_region} --name pc-eks",
      "echo '--Added new context arn:aws:eks:${var.aws_region}:918023795654:cluster/pc-eks to $HOME/.kube/config'"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"  # or the appropriate user for your AMI
      private_key = file("./keys")
      host        = self.public_ip
    }
  }
}

resource "aws_key_pair" "my-keys" {
  key_name   = "keys"
  public_key = var.public_key
}
resource "aws_eks_cluster" "eks" {
  name     = "pc-eks"
  role_arn = aws_iam_role.master.arn


  vpc_config {
    subnet_ids = [var.subnet_id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.AmazonEKSVPCResourceController,
    aws_iam_role_policy_attachment.AmazonEKSVPCResourceController,
    #aws_subnet.pub_sub1,
    #aws_subnet.pub_sub2,
  ]

}
resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "pc-node-group"
  node_role_arn   = aws_iam_role.worker.arn
  subnet_ids      = [var.subnet_id]
  capacity_type   = "ON_DEMAND"
  disk_size       = "20"
  instance_types  = ["t2.small"]

  remote_access {
    ec2_ssh_key               = "keys"
    source_security_group_ids = var.sg_for_jenkins
  }

  labels = tomap({ env = "dev" })

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    #aws_subnet.pub_sub1,
    #aws_subnet.pub_sub2,
  ]
}
resource "aws_iam_role" "master" {
  name = "ed-eks-master"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.master.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.master.name
}
resource "aws_iam_role" "worker" {
  name = "ed-eks-worker"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "autoscaler" {
  name   = "ed-eks-autoscaler-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeTags",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "x-ray" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.worker.name
}
resource "aws_iam_role_policy_attachment" "s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "autoscaler" {
  policy_arn = aws_iam_policy.autoscaler.arn
  role       = aws_iam_role.worker.name
}

resource "aws_iam_instance_profile" "worker" {
  depends_on = [aws_iam_role.worker]
  name       = "ed-eks-worker-new-profile1"
  role       = aws_iam_role.worker.name
}
