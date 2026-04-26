locals {
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "ec2",
    "elasticloadbalancing",
    "eks",
    # eks-auth is required for EKS Pod Identity in a fully-private VPC. The
    # Pod Identity Agent calls eks-auth.<region>.amazonaws.com to exchange
    # the projected SA token for AWS credentials. Missing this endpoint
    # silently breaks every workload that uses Pod Identity, even though
    # the agent daemonset itself starts cleanly. CLAUDE.md §2 omits it;
    # leaving it out makes "Pod Identity exclusively" impossible to honor.
    "eks-auth",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "logs",
  ]

  private_subnet_ids = [
    aws_subnet.this["private_a"].id,
    aws_subnet.this["private_b"].id,
  ]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-vpce-${replace(each.value, ".", "-")}"
  }
}
