# Support access policy

## Goals

- Every support session is attributable to a specific person.
- Keys are revocable in one place without redeploying the VPS.
- A leaked operator laptop key does not give long-term access to all clients.

## What gets installed where

The `deploy` user on each VPS has the SSH public keys listed in `infra/terraform.tfvars` (`ssh_public_keys`). Adding/removing keys requires a `terraform apply` — this is intentional, so key changes are auditable in version control.

## Adding a teammate

1. Get their SSH public key (the `.pub` file, not the private one). Ed25519 only — RSA is fine but Ed25519 is shorter and safer.
2. Append to `infra/terraform.tfvars`:
   ```hcl
   ssh_public_keys = [
     "ssh-ed25519 AAAA... operator@laptop",
     "ssh-ed25519 AAAA... newteammate@laptop",   # add me
   ]
   ```
3. `terraform -chdir=infra apply`. This is a per-client operation — repeat for every active client VPS.
4. Record the addition in this file:
   ```
   2026-05-17 — added newteammate@laptop (SHA256:abc...)
   ```

## Revoking access

Same flow in reverse: remove the line, `terraform apply` per client. Revocation is durable — the public key is not anywhere else on the VPS.

If a key is suspected leaked:

1. **Immediately** remove from every active client's `terraform.tfvars` and apply.
2. Rotate the operator's compute-provider and Cloudflare tokens.
3. Audit `~deploy/.ssh/authorized_keys` on each VPS to confirm the bad key is gone.
4. Scan `journalctl -u ssh` for sessions authenticated by the suspect key fingerprint.

## Key inventory

Update this list whenever a key changes. Treat the list as the source of truth — `terraform.tfvars` mirrors it.

| Owner | Comment | Fingerprint (SHA256) | Added | Removed |
|---|---|---|---|---|
| Dylan | `operator@laptop` | TBD | 2026-05-17 | — |

## What `deploy` can do

`sudoers` (in cloud-init) grants `deploy` NOPASSWD sudo only for:

- `/usr/bin/docker`
- `/usr/bin/docker compose`
- `/usr/bin/systemctl restart docker`

Everything else requires either a password (which `deploy` doesn't have — `lock_passwd: true`) or root. A compromised `deploy` session can:

- Read/restart containers
- Read `/opt/hermes-client/` contents (including `.env` — so secret rotation matters)

It cannot:

- Add users
- Modify firewall rules
- Install new packages
- Read other users' homes

For genuine root access (kernel updates, ufw changes), use the VPS provider's web console with rescue/recovery mode — there is no SSH path to root by design.

## Out of band

If SSH is completely broken (e.g. ufw misconfig locked out 22):

- Hetzner Cloud Console → server → "Rescue" — boot into rescue mode, mount the disk, fix the config.
- Vultr Customer Portal → instance → recovery/rescue options — boot into recovery mode, mount the disk, fix the config.
- Last resort: `terraform destroy` + `terraform apply` (data lost unless backed up).
