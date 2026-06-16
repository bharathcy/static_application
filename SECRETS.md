# GitHub Actions Secrets — EC2 Deployment

The [deploy workflow](.github/workflows/deploy.yml) syncs `index.html` and
`style.css` to the Nginx web root on your EC2 instance over SSH, then reloads
Nginx. The web root and Nginx config are **derived from the domain** you
provide:

| Derived from `DOMAIN` | Path |
| --------------------- | ---- |
| Web root              | `/var/www/<domain>` |
| Nginx server block    | `/etc/nginx/sites-available/<domain>` (symlinked into `sites-enabled`) |

If no Nginx config exists for the domain yet, the workflow **creates one
automatically** — an HTTPS config when a Let's Encrypt certificate is already
present for the domain, otherwise an HTTP-only config you can later upgrade with
Certbot. To make it run, add the following **repository secrets**.

## Where to add them

GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**. Add each name/value pair below.

## Required secrets

| Secret name      | Description                                              | Example                                  |
| ---------------- | -------------------------------------------------------- | ---------------------------------------- |
| `EC2_HOST`       | Public IP **or** domain of the EC2 instance.             | `13.234.56.78` or `profile.example.com`  |
| `EC2_USER`       | SSH login user on the instance.                          | `ubuntu` (Ubuntu) / `ec2-user` (Amazon Linux) |
| `EC2_SSH_KEY`    | **Private** SSH key (full PEM contents) that can log in. | contents of `your-key.pem` (see below)   |
| `DOMAIN`         | Domain to serve. Drives the web root **and** the Nginx config name. | `profile.example.com`           |

## Optional secrets

| Secret name | Description                                  | Default |
| ----------- | ------------------------------------------- | ------- |
| `EC2_PORT`  | SSH port, if not the default. Add only if you changed it. | `22`    |

---

## Preparing each value

### `EC2_SSH_KEY` — the private key

Paste the **entire** private key, including the header and footer lines.

```bash
# Print the key so you can copy it (run on your local machine)
cat ~/.ssh/your-ec2-key.pem
```

It should look like:

```
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA...
...many lines...
-----END RSA PRIVATE KEY-----
```

> 💡 The matching **public** key must be in `~/.ssh/authorized_keys` for
> `EC2_USER` on the instance. If you launched the instance with this key pair,
> that's already the case.

### `DOMAIN` — the domain to serve

Just the bare domain, e.g. `profile.example.com` (no `https://`, no trailing
slash). The workflow uses it to derive everything:

- **Web root:** `/var/www/profile.example.com`
- **Nginx config:** `/etc/nginx/sites-available/profile.example.com`, symlinked
  into `sites-enabled/`
- **SSL paths** (when present): `/etc/letsencrypt/live/profile.example.com/`

The generated server block also responds to the `www.` variant. If a config for
the domain already exists, the workflow **leaves it untouched** and only updates
the files — so any Certbot-managed config you already have is safe.

---

## One-time server preparation

The workflow does the rest — it **installs Nginx** (if missing), creates the web
root, writes the server block, and reloads Nginx. It just needs the deploy user
to run `sudo` **without an interactive password prompt** (it installs packages,
edits `nginx.conf`, and manages the site). Grant that once on the instance:

```bash
# Allow the deploy user to run sudo without a password prompt.
# Use a DEDICATED deploy user for this — it is broad by design so a single
# push can install and configure everything.
sudo tee /etc/sudoers.d/deploy >/dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/deploy
```

That's it. Nothing else is required — no pre-installed Nginx, no pre-created web
root or config.

> **SSL:** if a Let's Encrypt certificate already exists for the domain
> (`/etc/letsencrypt/live/<domain>/`), the workflow writes an HTTPS config that
> uses it. If not, it writes an HTTP-only config; enable TLS afterwards with
> `sudo certbot --nginx -d <domain>` and the next push picks up the cert
> automatically.

---

## Verifying the deployment

1. Push a change to `main` (or run the workflow manually via **Actions →
   Deploy to AWS EC2 → Run workflow**).
2. Watch the run under the repo's **Actions** tab.
3. Visit `https://your-domain` — the updated profile page should be live over
   HTTPS.

## Security checklist

- Use a **dedicated deploy key**, not your personal key, if possible.
- Restrict the EC2 **security group** so SSH (port 22) is reachable from
  GitHub-hosted runners or your IP only.
- Never commit the private key to the repo — it lives **only** in GitHub
  Secrets.
