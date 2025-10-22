
# Output dos IPs públicos das instâncias EC2
output "leopoldo_ec2_public_ips" {
  description = "Lista de IPs públicos das instâncias leopoldo"
  value       = aws_instance.leopoldo_ec2[*].public_ip
}

# Output dos nomes (tags) das instâncias EC2
output "leopoldo_ec2_names" {
  description = "Nomes das instâncias criadas"
  value       = aws_instance.leopoldo_ec2[*].tags["Name"]
}

