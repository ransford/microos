output "ami" {
  value = "${data.aws_ami.ubuntu.name} (${data.aws_ami.ubuntu.id})"
}

output "instance_ids" {
  value = aws_instance.builder[*].id
}

output "private_ips" {
  value = aws_instance.builder[*].private_ip
}

output "tailscale_hostnames" {
  description = "Hostnames the instances register with on your tailnet."
  value       = [for i in range(var.instance_count) : "${var.name}-${i}"]
}
