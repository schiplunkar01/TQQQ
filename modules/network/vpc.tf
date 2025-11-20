data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }

locals { azs = slice(data.aws_availability_zones.available.names, 0, 3) }

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "secscan-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "secscan-igw" }
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : idx => az }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.key)
  map_public_ip_on_launch = true
  availability_zone       = each.value
  tags = { Name = "public-${each.value}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : idx => az }
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.key + 8)
  availability_zone = each.value
  tags = { Name = "private-${each.value}", Tier = "private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "public-rt" }
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

# NAT per AZ
resource "aws_eip" "nat" {
  for_each = var.nat_strategy == "per_az" ? aws_subnet.public : {}
  domain   = "vpc"
  tags     = { Name = "nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "nat" {
  for_each      = var.nat_strategy == "per_az" ? aws_subnet.public : {}
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  tags          = { Name = "nat-${each.key}" }
  depends_on    = [aws_internet_gateway.igw]
}

# Single NAT
resource "aws_eip" "nat_single" {
  count  = var.nat_strategy == "single" ? 1 : 0
  domain = "vpc"
  tags   = { Name = "nat-eip-single" }
}

resource "aws_nat_gateway" "nat_single" {
  count         = var.nat_strategy == "single" ? 1 : 0
  allocation_id = aws_eip.nat_single[0].id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = { Name = "nat-single" }
  depends_on    = [aws_internet_gateway.igw]
}

# Private route tables per AZ
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "private-rt-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_strategy == "per_az" ? aws_nat_gateway.nat[tonumber(each.key)].id : aws_nat_gateway.nat_single[0].id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = each.value.id
}

# S3 Gateway VPC endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id],[for _, rt in aws_route_table.private : rt.id])
  tags = { Name = "secscan-s3-endpoint" }
}
