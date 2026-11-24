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

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "ai_voice_sg" {
  name        = "ai-voice-assistant-demo-sg"
  description = "Security group for AI Voice Assistant demo"
  vpc_id      = data.aws_vpc.default.id

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
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.ai_voice_sg.id]

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