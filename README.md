# DevOps Engineer Profile — Static Site

A clean, responsive profile page built with **Bootstrap 5** and custom CSS,
auto-deployed to an **AWS EC2** instance (Nginx + HTTPS) via **GitHub Actions**.

## 📁 Project structure

```
static_application/
├── index.html                  # Profile page markup
├── style.css                   # Custom styling (gradients, timeline, skills)
├── README.md                   # This file
├── SECRETS.md                  # GitHub secrets needed for deployment
└── .github/
    └── workflows/
        └── deploy.yml          # CI/CD: deploy to EC2 on push to main
```

## 🚀 Deployment

A single push to `main` (or a manual trigger) provisions everything. GitHub
Actions:

1. Connects to the EC2 instance over SSH.
2. **Installs Nginx** if it isn't already present.
3. Creates the web root (`/var/www/<domain>`) and **writes the Nginx server
   block** for the `DOMAIN` — HTTPS when a Let's Encrypt cert is present for the
   domain, otherwise HTTP-only.
4. Syncs `index.html` and `style.css` into the web root with `rsync`.
5. Validates the Nginx config and reloads it.

Every step is idempotent and derived from the single `DOMAIN` secret, so a fresh
EC2 instance goes from bare to live with one push, and pointing the site at a new
domain is just a secrets change.

### Setup

1. Configure the repository secrets listed in **[SECRETS.md](SECRETS.md)**.
2. Run the one-time server preparation steps in that same file.
3. Push to `main` — the workflow does the rest.

## 🛠️ Local preview

It's a static site — just open `index.html` in a browser, or serve it:

```bash
python3 -m http.server 8080
# then visit http://localhost:8080
```

## 🧰 Tech stack

- Bootstrap 5.3 + Bootstrap Icons (via CDN)
- Inter font (Google Fonts)
- Custom CSS
- GitHub Actions · AWS EC2 · Nginx · Let's Encrypt
