# GitHub Actions Secrets — EC2 Deployment

The [deploy workflow](.github/workflows/deploy.yml) syncs `index.html` and
`style.css` to `/var/www/<domain>` on your EC2 instance over SSH, then reloads
Nginx. Nginx setup and SSL are handled by your server-side scripts. Add the
following **repository secrets** to make it run.

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
slash). The workflow deploys the files to `/var/www/<domain>`, which should
match the web root your Nginx setup script serves.

---

## One-time server preparation

Nginx and SSL are set up by your server-side scripts. The workflow only needs
the deploy user to reload Nginx without a password prompt:

```bash
echo "$USER ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx" \
  | sudo tee /etc/sudoers.d/deploy-nginx
sudo chmod 440 /etc/sudoers.d/deploy-nginx
```

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
