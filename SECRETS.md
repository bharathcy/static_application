# GitHub Actions Secrets — EC2 Deployment

The [deploy workflow](.github/workflows/deploy.yml) syncs `index.html` and
`style.css` to the Nginx web root on your EC2 instance over SSH, then reloads
Nginx. To make it run, add the following **repository secrets**.

## Where to add them

GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**. Add each name/value pair below.

## Required secrets

| Secret name      | Description                                              | Example                                  |
| ---------------- | -------------------------------------------------------- | ---------------------------------------- |
| `EC2_HOST`       | Public IP **or** domain of the EC2 instance.             | `13.234.56.78` or `profile.example.com`  |
| `EC2_USER`       | SSH login user on the instance.                          | `ubuntu` (Ubuntu) / `ec2-user` (Amazon Linux) |
| `EC2_SSH_KEY`    | **Private** SSH key (full PEM contents) that can log in. | contents of `your-key.pem` (see below)   |
| `EC2_TARGET_DIR` | Nginx web root the files are served from.                | `/var/www/profile.example.com`           |

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

### `EC2_TARGET_DIR` — the web root

This must match the `root` directive in your Nginx server block for the domain,
e.g. in `/etc/nginx/sites-available/profile.example.com`:

```nginx
server {
    server_name profile.example.com;
    root /var/www/profile.example.com;   # <-- this is EC2_TARGET_DIR
    index index.html;
    # ... SSL config managed by Certbot ...
}
```

---

## One-time server preparation

Run these **on the EC2 instance** so the deploy user can write the web root and
reload Nginx without an interactive password.

```bash
# 1. Create the web root and let your deploy user own it
sudo mkdir -p /var/www/profile.example.com
sudo chown -R $USER:$USER /var/www/profile.example.com

# 2. Allow Nginx reload without a password prompt (needed by the workflow)
echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /bin/systemctl reload nginx" \
  | sudo tee /etc/sudoers.d/deploy-nginx
sudo chmod 440 /etc/sudoers.d/deploy-nginx

# 3. Make sure rsync is installed (GitHub runner already has it)
sudo apt-get update && sudo apt-get install -y rsync   # Ubuntu
# sudo yum install -y rsync                              # Amazon Linux
```

> Nginx installation and SSL certificates (Certbot / Let's Encrypt) are assumed
> to be **already configured** for the domain — the workflow only updates the
> static files and reloads Nginx.

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
