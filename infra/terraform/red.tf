locals {
  nombre = "energia-db"
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}

resource "aws_vpc" "principal" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # el endpoint de RDS debe resolver a la IP publica

  tags = { Name = "${local.nombre}-vpc" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id

  tags = { Name = "${local.nombre}-igw" }
}

resource "aws_subnet" "publica" {
  count = 2

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = cidrsubnet(aws_vpc.principal.cidr_block, 8, count.index) # 10.20.0.0/24 y 10.20.1.0/24
  availability_zone       = data.aws_availability_zones.disponibles.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.nombre}-publica-${count.index + 1}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = { Name = "${local.nombre}-publica" }
}

resource "aws_route_table_association" "publica" {
  count = 2

  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

resource "aws_db_subnet_group" "principal" {
  name       = "${local.nombre}-subnets"
  subnet_ids = aws_subnet.publica[*].id

  tags = { Name = "${local.nombre}-subnets" }
}

resource "aws_security_group" "db" {
  name        = "${local.nombre}-db"
  description = "PostgreSQL 5432 solo desde IPs permitidas"
  vpc_id      = aws_vpc.principal.id

  tags = { Name = "${local.nombre}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.db.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL desde ${each.value}"
}
