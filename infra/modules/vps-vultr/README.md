# Vultr VPS Module

Creates the Vultr side of a single-client Hermes deployment:

- SSH keys from the operator public keys.
- Firewall group allowing SSH from `allowed_ssh_cidrs` and public HTTP/HTTPS.
- One Ubuntu Cloud Compute instance with IPv6 enabled.
- Cloud-init user-data passed through from the root module.

Defaults are chosen to match the validated manual smoke test:

- Region: `ord` (Chicago)
- Plan: `vc2-2c-4gb`
- OS: Ubuntu 24.04 LTS (`2284`)
- Vultr automatic backups: `disabled`

Backups stay disabled by default because they are a paid Vultr add-on and the
repo has its own backup milestone.
