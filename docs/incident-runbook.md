# Incident runbook

Status: **M5 stub.** Comprehensive incident playbook written after M5 hardening.

## Triage flowchart (M1-level)

1. **Can you `curl https://<fqdn>/health`?**
   - No → DNS issue, firewall issue, or VPS down. Check `dig <fqdn>` and the selected VPS provider console.
   - Yes but wrong content → app issue. SSH in.

2. **`ssh deploy@<ip>` works?**
   - No → use provider console rescue/recovery. Check ufw, fail2ban.
   - Yes → continue.

3. **`sudo docker compose ps` shows healthy containers?**
   - Anything `exited` → `sudo docker compose logs <service> --tail=200`.
   - All healthy but bad behaviour → app logs, or it's a config drift.

4. **Recent change?**
   - Yes → rollback per `docs/rollback.md`.
   - No → escalate.

## Common one-liners

```bash
# Tail all compose logs
ssh deploy@<ip> 'cd /opt/hermes-client/compose && sudo docker compose logs --tail=200 --follow'

# Restart everything
ssh deploy@<ip> 'cd /opt/hermes-client/compose && sudo docker compose restart'

# Check disk usage
ssh deploy@<ip> 'df -h && sudo docker system df'

# Check who's been logging in
ssh deploy@<ip> 'last -n 20'

# Check fail2ban bans
ssh deploy@<ip> 'sudo fail2ban-client status sshd'
```

## Severity guidance (placeholder — refine post-M5)

| Severity | Definition | Response time |
|---|---|---|
| SEV-1 | Client cannot use Hermes at all | 1 hour |
| SEV-2 | Degraded but partially functional | 4 hours |
| SEV-3 | Cosmetic / non-blocking | Next business day |

Until SLA is contractually defined, treat all alerts as SEV-2 unless explicitly told otherwise.
