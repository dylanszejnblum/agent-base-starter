# M3 deploy runbook

End-to-end walkthrough for the M3 deploy: M2's Hermes stack + age-encrypted per-client secrets + pinned Hermes image SHA.

End state: same operational target as M2 (`https://<slug>.<domain>/` behind basic_auth, valid LE cert), but secrets are reproducible, the image is reproducible, and rerunning a deploy doesn't generate a new dashboard password.

## What changed vs M2

| | M2 | M3 |
|---|---|---|
| Hermes image | `:main` (floating) | `:sha-d9b6f75c...` (pinned) |
| Secrets at rest | inline operator env vars | `secrets/<slug>.env.age` (encrypted, in repo) |
| Dashboard password | regenerated every deploy | stable, stored encrypted, rotated explicitly |
| Plaintext password on disk | `.deploy-credentials/<slug>.txt` (mode 600) | never |
| First-time client setup | `export OPENAI_API_KEY=... && ./bin/deploy-client` | interactive prompt the first time, auto on subsequent runs |
| Repo-tracked secrets dir | n/a | `secrets/` — encrypted .age + .recipients + README |
| `templates/client.env.tmpl` | existed | removed (age workflow makes it obsolete) |

## Prerequisites (delta from M2)

| Requirement | How to verify |
|---|---|
| `age` installed locally | `command -v age && age --version` (macOS: `brew install age`; Debian: `apt install age`) |
| age key generated | `ls -la ~/.config/age/operator.key` |
| Public key in `secrets/.recipients` | `grep "$(age-keygen -y ~/.config/age/operator.key)" secrets/.recipients` |

## One-time operator setup

```bash
# 1. Install age (macOS)
brew install age

# 2. Generate operator key
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/operator.key
chmod 600 ~/.config/age/operator.key

# 3. Read the public key (starts with age1...)
age-keygen -y ~/.config/age/operator.key
# example: age1qm6gkr67p8vqz4nws0pzjzrqkj3hxdkpjjxdcs07pfekm3wzy3cs2t73h7

# 4. Append it to secrets/.recipients
{
  echo ""
  echo "# Dylan — laptop @ $(date +%Y-%m-%d)"
  age-keygen -y ~/.config/age/operator.key
} >> secrets/.recipients

git add secrets/.recipients
git commit -m "ops: add operator age key (dylan)"
```

## Deploy

```bash
export HCLOUD_TOKEN='...'
export CLOUDFLARE_API_TOKEN='...'
export OPENAI_API_KEY='sk-...'         # only needed for first-time init of this slug

./bin/deploy-client demo --domain example.com
```

What you should see, first time for a new slug:

```
[info] slug=demo fqdn=demo.example.com location=nbg1 size=cx22 image_tag=m3-age
[info] no encrypted secrets for demo — initialising secrets/demo.env.age
[ok]   wrote secrets/demo.env.age
[warn] remember to: git add secrets/demo.env.age && git commit -m 'ops: init demo secrets'
[info] terraform init
[info] terraform apply
...
[info] bcrypt-hashing dashboard password (via disposable caddy container)
...
[ok]   deploy complete
[info] URL:        https://demo.example.com/
[info] SSH:        ssh deploy@203.0.113.42
[info] username:   ops
[info] password:   stored in secrets/demo.env.age
[info]
[info] to read the password:
[info]   age -d -i ~/.config/age/operator.key secrets/demo.env.age | grep HERMES_DASHBOARD_PASSWORD
```

Commit the encrypted secrets file:

```bash
git add secrets/demo.env.age
git commit -m "ops: init demo secrets"
```

On subsequent deploys of the **same slug** there's no interactive prompt — the encrypted file already exists and the deploy is fully non-interactive.

## Reading the dashboard password

```bash
age -d -i ~/.config/age/operator.key secrets/demo.env.age | grep HERMES_DASHBOARD_PASSWORD
# HERMES_DASHBOARD_PASSWORD=kJ8xq3pPbN2vR4fT9wYsLz
```

Pipe to `pbcopy` (macOS) or `wl-copy` (Linux Wayland) to get it onto the clipboard.

## Editing secrets (e.g. add a new LLM key)

```bash
plain="$(mktemp)"
age -d -i ~/.config/age/operator.key secrets/demo.env.age > "$plain"
$EDITOR "$plain"
age -R secrets/.recipients -o secrets/demo.env.age "$plain"
rm -P "$plain"   # or: shred -u "$plain" on Linux

# Apply: containers pick up new env on restart.
./bin/deploy-client demo --domain example.com

git add secrets/demo.env.age
git commit -m "ops: rotate demo openai key"
```

## Adding another operator

1. New operator runs the one-time setup, generates their key, sends you the **public** key.
2. You append their public key to `secrets/.recipients` with a comment line.
3. Re-encrypt every `secrets/*.env.age` so the new key can also decrypt:

   ```bash
   for f in secrets/*.env.age; do
     plain="$(mktemp)"
     age -d -i ~/.config/age/operator.key "$f" > "$plain"
     age -R secrets/.recipients -o "$f" "$plain"
     rm -P "$plain"
   done
   git add secrets/*.env.age secrets/.recipients
   git commit -m "ops: re-encrypt secrets for new recipient (<name>)"
   ```

4. Push. New operator clones and can decrypt with their own key.

## Pinning Hermes to a different version

Current pin: `nousresearch/hermes-agent:sha-d9b6f75c0b0ffa3cdb3cbe63de3a8e1a5aa44e8f`.

To bump:

1. Check the new tag at https://hub.docker.com/r/nousresearch/hermes-agent/tags.
2. Update three places:
   - `compose/docker-compose.yml` (two `image:` lines)
   - `compose/.env.example` (`HERMES_IMAGE=...`)
   - `bin/deploy-client` (the `HERMES_IMAGE_DEFAULT=` constant)
3. Open a PR. Test on a throwaway deploy. Merge to `develop`, release to `main`.

You can also override per-deploy without changing the default:

```bash
./bin/deploy-client demo --domain example.com \
  --hermes-image nousresearch/hermes-agent:sha-<other>
```

## Common failure modes (M3-specific)

### `age key not found at ~/.config/age/operator.key`

You haven't done the one-time setup yet. Do it.

### `no recipients in secrets/.recipients`

Append your public key:

```bash
age-keygen -y ~/.config/age/operator.key >> secrets/.recipients
```

### `secrets/<slug>.env.age` exists but decrypt fails

Your operator key is not in `.recipients`. Either:

- another operator must re-encrypt the file with your key added (see "Adding another operator"), or
- regenerate the secret from scratch: `rm secrets/<slug>.env.age && ./bin/deploy-client <slug> --domain ...` (loses old password — you'll get a new one on init).

### `caddy hash-password produced empty hash`

Docker isn't running locally. Start Docker Desktop / `systemctl start docker` and retry.

### Smoke test fails: dashboard returns 401 with correct creds

Possible causes:

- Hash didn't render correctly in `.env`. Check on the VPS: `sudo grep HERMES_DASHBOARD /opt/hermes-client/compose/.env`. Should be ~60 chars starting `$2a$14$`.
- The password in the encrypted file is wrong. Decrypt and compare to what you're typing.

## Teardown

Unchanged from M2:

```bash
./bin/destroy-client demo --domain example.com
```

The encrypted `secrets/demo.env.age` stays in the repo. It's safe to leave (it's encrypted) and useful if you redeploy the same slug later. If you want a clean slate, `git rm secrets/demo.env.age && git commit`.

## What's NOT in M3

- Off-VPS backups (M4)
- Hermes profile distributions (`--profile-distribution` flag) — deferred to first TenderClaw work
- Custom UI container (TenderClaw repo)
- Hardening pass + image vulnerability scans (M5)
