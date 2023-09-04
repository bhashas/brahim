#Première partie :

provider "aws" {
  region = "eu-west-1"
}

resource "aws_vpc" "vpc-epsi" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc-epsi-tf"
  }
}

resource "aws_subnet" "private-a" {
  vpc_id     = aws_vpc.vpc-epsi.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "private-a-tf"
  }
}

resource "aws_subnet" "private-b" {
  vpc_id     = aws_vpc.vpc-epsi.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1b"
  tags = {
    Name = "private-b-tf"
  }
}

resource "aws_subnet" "public-a" {
  vpc_id     = aws_vpc.vpc-epsi.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "public-a-tf"
  }
}

resource "aws_subnet" "public-b" {
  vpc_id     = aws_vpc.vpc-epsi.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "eu-west-1b"
  tags = {
    Name = "public-b-tf"
  }
}

#Seconde partie :

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc-epsi.id

  tags = {
    Name = "igw-epsi-tf"
  }
}

resource "aws_route_table" "rt-epsi" {
  vpc_id = aws_vpc.vpc-epsi.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "rt-epsi-tf"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-a.id
  route_table_id = aws_route_table.rt-epsi.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public-b.id
  route_table_id = aws_route_table.rt-epsi.id
}

#ip publique subnet publique key pair ec2-key
resource "aws_instance" "web" {
  ami           = "ami-01dd271720c1ba44f"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public-b.id
  associate_public_ip_address = true
  key_name      = aws_key_pair.deployer.key_name
  user_data     = file("${path.module}/apache.sh")
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "webserver-tf"
  }
}

resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "ec2-key-tf"
  public_key = tls_private_key.rsa-4096-example.public_key_openssh
}

output "public-ip" {
  value = aws_instance.web.public_ip
} 

#Troisème Partie

# Création du groupe de sous-réseaux de base de données
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "database-1"
  subnet_ids = [aws_subnet.private-a.id, aws_subnet.private-b.id]
}


# Création du groupe de sécurité pour le serveur Web
resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSecurityGroup"
  description = "Security group to allow web server access"
  vpc_id      = var.vpc_id 
  # Règle pour autoriser l'accès depuis n'importe quelle source sur le port 80 (HTTP)
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Règle pour autoriser l'accès sortant vers toutes les destinations
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Spécifiez l'ID de la VPC existante
variable "vpc_id" {
  default = "vpc-08f6fbd2fcc2440d8"  # Remplacez par l'ID de votre VPC
}
# Création du groupe de sécurité pour l'instance RDS
resource "aws_security_group" "rds_instance_sg" {
  name        = "RDSInstanceSecurityGroup"
  description = "Security group to allow RDS access"
  vpc_id      = var.vpc_id
  # Règle pour autoriser l'accès entrant depuis le groupe de sécurité du serveur web sur le port 3306 (MySQL)
  ingress {
    description = "MySQL access from web server"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  # Règle pour autoriser l'accès sortant vers toutes les destinations
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Création de l'instance RDS

resource "aws_db_instance" "rdsTp" {
  identifier            = "my-rds-instance"
  engine                = "mysql"
  engine_version        = "5.7"
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  
  instance_class        = "db.t2.micro"
  db_name                  = "myrdsdatabase"
  username              = "dbadmin"
  password              = random_password.secret.result 
  allocated_storage     = 20
  storage_type          = "gp2"
  multi_az              = false
  publicly_accessible   = false
  vpc_security_group_ids =[aws_security_group.rds_instance_sg.id] # Utilisez la variable pour spécifier l'ID du groupe de sécurité RDS
}

#Appel de la fonction random 

resource "random_password" "secret" {
  length           = 16
  special          = true
  
}
