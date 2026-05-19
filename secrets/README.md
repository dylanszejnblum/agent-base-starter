# `secrets/` — age-encrypted per-client env files

Each client/deploy has its secrets in `secrets/<slug>.env.age` — an
[age](https://age-encryption.org)-encrypted `.env` file. Encrypted files
**are committed to the repo**; only the corresponding age private key can
decrypt them.

## What lives here

| File | Tracked? | Purpose |
|---|---|---|
| `<slug>.env.age` | yes (encrypted) | per-deploy secrets — dashboard password, LLM keys, integration tokens |
| `.recipients` | yes | age public keys allowed to decrypt files in this dir |
| `<slug>.env` | **no** (gitignored) | plaintext, never persisted by deploy-client; ephemeral only |
| `.env.example` | yes | schema reference — required + optional variables |

## Variables in `<slug>.env.age`

After decryption the file is a standard `.env`. Required:

```ini
HERMES_DASHBOARD_PASSWORD=<plaintext password>
OPENAI_API_KEY=sk-...        # OR ANTHROPIC_API_KEY (at least one)
```

Optional:

```ini
ANTHROPIC_API_KEY=sk-ant-...
# future client-integration keys, MCP tokens, etc.
```

`bin/deploy-client` bcrypt-hashes `HERMES_DASHBOARD_PASSWORD` at deploy time
and writes `HERMES_DASHBOARD_PASSWORD_HASH` into the VPS-side `.env`, escaping
`$` as `$$` so Docker Compose does not mangle the bcrypt value. The plaintext
never leaves your machine.

## Workflow

### One-time setup (per operator machine)

```bash
# 1. Install age (macOS: brew install age; Debian: apt install age)

# 2. Generate a key
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/operator.key
chmod 600 ~/.config/age/operator.key

# 3. Read your public key (starts with age1...)
age-keygen -y ~/.config/age/operator.key

# 4. Append it to secrets/.recipients (one per line, with a comment)
echo "# Dylan — laptop @ $(date +%Y-%m-%d)" >> secrets/.recipients
age-keygen -y ~/.config/age/operator.key >> secrets/.recipients
git add secrets/.recipients
git commit -m "ops: add operator age key (dylan)"
```

### Per-client init (first deploy of a new slug)

`bin/deploy-client <slug> --domain ...` detects missing
`secrets/<slug>.env.age` and walks you through creating it interactively:

- prompts (or reads from env) for `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`
- generates a random 24-char dashboard password
- encrypts to `secrets/<slug>.env.age`
- prints the password **once**, suggests you store it in your password manager

After init, the file is committed:

```bash
git add secrets/<slug>.env.age
git commit -m "ops: init <slug> secrets"
```

### Editing an existing secret

```bash
age -d -i ~/.config/age/operator.key secrets/<slug>.env.age > /tmp/<slug>.env
$EDITOR /tmp/<slug>.env
age -R secrets/.recipients -o secrets/<slug>.env.age /tmp/<slug>.env
shred -u /tmp/<slug>.env  # macOS: rm -P /tmp/<slug>.env
git add secrets/<slug>.env.age
git commit -m "ops: rotate <slug> openai key"
```

### Adding a new operator

1. New operator runs the one-time setup, generates their key, sends you the public key.
2. You append their public key to `.recipients` and commit.
3. You re-encrypt every existing `.env.age` so the new key can also decrypt:

   ```bash
   for f in secrets/*.env.age; do
     plain="$(mktemp)"
     age -d -i ~/.config/age/operator.key "$f" > "$plain"
     age -R secrets/.recipients -o "$f" "$plain"
     shred -u "$plain"
   done
   git add secrets/*.env.age
   git commit -m "ops: re-encrypt secrets for new recipient"
   ```

### Rotating a leaked operator key

1. Remove the leaked public key line from `.recipients`. Commit.
2. Re-encrypt every `.env.age` (same loop as above) so the leaked key can no longer decrypt new versions.
3. Rotate the actual secrets inside each `.env.age` (LLM keys, dashboard passwords) — the leaked key holder may have decrypted earlier versions before rotation.

Past commits remain decryptable by the leaked key. If the threat model
requires historical secrecy, rotate the underlying secrets (which you'd
do anyway) — the encrypted blobs in git history become useless.

## Why age and not 1Password / SOPS

- **age**: zero infra, files in git, simple CLI, single tool. Best fit for solo dev.
- **SOPS + age**: same crypto, adds YAML key-level encryption. Worth it only for structured config beyond `.env`.
- **1Password CLI**: better UX for teams, but $4–8/mo and no git-versioned audit trail. Migrate later if/when needed.
