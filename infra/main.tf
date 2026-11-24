terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"

  default_tags {
    tags = {
      Project     = "ai-voice-assistant-demo"
      Environment = "demo"
      ManagedBy   = "Terraform"
    }
  }
}

# Fetch latest Ubuntu 24.04 AMI via SSM Parameter Store (avoids blocked DescribeImages)
data "aws_ssm_parameter" "ubuntu_24_04" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Dedicated VPC (required because no default VPC exists in ap-southeast-2)
resource "aws_vpc" "demo_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ai-voice-demo-vpc"
  }
}

resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_vpc.id

  tags = {
    Name = "ai-voice-demo-igw"
  }
}

resource "aws_subnet" "demo_public_subnet" {
  vpc_id                  = aws_vpc.demo_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "ai-voice-demo-public-subnet"
  }
}

resource "aws_route_table" "demo_public_rt" {
  vpc_id = aws_vpc.demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_igw.id
  }

  tags = {
    Name = "ai-voice-demo-public-rt"
  }
}

resource "aws_route_table_association" "demo_public_rta" {
  subnet_id      = aws_subnet.demo_public_subnet.id
  route_table_id = aws_route_table.demo_public_rt.id
}

resource "aws_security_group" "ai_voice_sg" {
  name        = "ai-voice-assistant-demo-sg"
  description = "Security group for AI Voice Assistant demo"
  vpc_id      = aws_vpc.demo_vpc.id

  ingress {
    description = "SSH / EC2 Instance Connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FastAPI Direct Port"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ai_voice_server" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ubuntu_24_04.value)
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.demo_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.ai_voice_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
              #!/bin/bash
              set -e
              apt-get update -y
              apt-get install -y git curl nginx ffmpeg python3 python3-pip python3-venv
              curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
              apt-get install -y nodejs
              npm install -g pm2

              mkdir -p /opt/ai-voice-assistant
              git clone https://github.com/AjayVarma03/ai-voice-assistant.git /opt/ai-voice-assistant
              chown -R ubuntu:ubuntu /opt/ai-voice-assistant

              cd /opt/ai-voice-assistant/backend
              python3 -m venv venv
              ./venv/bin/pip install --upgrade pip
              ./venv/bin/pip install -r requirements.txt

              su - ubuntu -c "cd /opt/ai-voice-assistant/backend && pm2 start './venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000' --name ai-voice-backend && pm2 save"
              env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu

              cat << 'NGINX' > /etc/nginx/sites-available/ai-voice
              server {
                  listen 80;
                  server_name _;
                  client_max_body_size 25M;
                  location / {
                      proxy_pass http://127.0.0.1:8000;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection "upgrade";
                      proxy_set_header Host $host;
                  }
              }
              NGINX

              ln -sf /etc/nginx/sites-available/ai-voice /etc/nginx/sites-enabled/ai-voice
              rm -f /etc/nginx/sites-enabled/default
              nginx -t && systemctl restart nginx
              USERDATA

  tags = {
    Name = "ai-voice-assistant-demo-ec2"
  }
}

output "public_ip" {
  value = aws_instance.ai_voice_server.public_ip
}

output "app_url" {
  value = "http://${aws_instance.ai_voice_server.public_ip}"
}