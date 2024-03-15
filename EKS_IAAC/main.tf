module "networking" {
  source               = "./Modules/netwoking"
  vpc_cidr             = var.vpc_cidr
  vpc_name             = var.vpc_name
  cidr_public_subnet   = var.cidr_public_subnet
  cidr_private_subnet  = var.cidr_private_subnet
}
module "security_group" {
  source              = "./Modules/security-groups"
  ec2_sg_name         = "SG for EC2 to enable SSH(22), HTTPS(443) and HTTP(80)"
  vpc_id              = module.networking.dev_proj_1_vpc_id
  eks_sg_name         = "Allow port 8080 for jenkins"
}
module "Eks" {
  source                    = "./Modules/Eks"
  instance_type             = "t2.medium"
  tag_name                  = "Eks:Ubuntu Linux EC2"
  public_key                = var.public_key
  aws_access_key            = var.aws_access_key
  aws_secret_key            = var.aws_secret_key
  aws_region                = var.aws_region
  enable_public_ip_address  = true
  subnet_id                 = tolist(module.networking.dev_proj_1_public_subnets)[0]  # Make sure this is correctly defined
  sg_for_jenkins            = [module.security_group.sg_ec2_sg_ssh_http_id, module.security_group.sg_ec2_jenkins_port_8080]
}

