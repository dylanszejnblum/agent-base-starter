# Network-level firewall enforced at Hetzner edge. Host-level ufw is a defence
# in depth (configured by cloud-init) and should mirror these rules.
#
# Inbound: SSH from allowlist, HTTP+HTTPS from anywhere (Let's Encrypt needs 80
# reachable for HTTP-01 challenges; 443 for the actual service).
# Outbound: default Hetzner policy is fully open; we don't constrain it here.
resource "hcloud_firewall" "client" {
  name   = "${var.slug}-fw"
  labels = var.labels

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ssh_cidrs
    description = "SSH"
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTP — ACME HTTP-01 and HTTPS redirect"
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTPS"
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "ICMP — diagnostics"
  }
}
