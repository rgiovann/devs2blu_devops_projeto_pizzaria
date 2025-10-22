# Busca a AMI oficial do Debian 12 em us-east-2
data "aws_ami" "debian12" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }
}

# Busca a VPC existente
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["devops-2sem2025-vpc"]
  }
}

# Busca a subnet existente
data "aws_subnet" "public1" {
  filter {
    name   = "tag:Name"
    values = ["devops-2sem2025-subnet-public1-us-east-2a"]
  }
}

# Security Group
resource "aws_security_group" "leopoldo_sg" {
  description = "SG para EC2s leopoldo com SSH restrito e HTTP/ICMP"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "SSH aberto"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP aberto"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "Acesso aplicaco (porta 8080)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

  ingress {
    description = "ICMP (ping)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "leopoldo-sg-pizzaria-gihub-actions-2025"
  }
}

# Cria uma instancia pizzaria
resource "aws_instance" "leopoldo_ec2" {
  count         = 1
  ami           = data.aws_ami.debian12.id
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnet.public1.id
  vpc_security_group_ids = [aws_security_group.leopoldo_sg.id]
  associate_public_ip_address = true
  key_name = "leopoldo-key-pizzaria"

  # User data minimalista (apenas tags para identificação)
  user_data = <<-EOF
    #!/bin/bash
    echo "Instancia provisionada em $(date)" > /var/log/provision.log
  EOF

  # Evita recriação desnecessária
  lifecycle {
    ignore_changes = [user_data, ami]
  }

  tags = {
    Name = "leopoldo-ec2-pizzaria-github-actions"
  }

}

# Adicione no final do arquivo
output "destroy_command" {
  description = "Comando para destruir a infraestrutura"
  value       = "cd infra/terraform && terraform destroy -auto-approve"
}
