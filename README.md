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

On every push to `main` (or a manual trigger), GitHub Actions:

1. Connects to the EC2 instance over SSH.
2. Ensures the web root (`/var/www/<domain>`) and an Nginx server block for the
   `DOMAIN` exist — **creating the config automatically** if it's missing
   (HTTPS when a Let's Encrypt cert is present, otherwise HTTP-only).
3. Syncs `index.html` and `style.css` into the web root with `rsync`.
4. Validates the Nginx config and reloads it.

Everything is derived from the single `DOMAIN` secret, so pointing the site at a
new domain is just a secrets change. The site is served over HTTPS using the SSL
certificate configured on the instance for that domain.

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
