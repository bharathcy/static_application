# DevOps Engineer Profile — Static Site

A clean, responsive profile page built with **Bootstrap 5** and custom CSS,
auto-deployed to an **AWS EC2** instance (Nginx + HTTPS) via **GitHub Actions**.

## 📁 Project structure

```
static_application/
├── index.html                       # Profile page markup
├── style.css                        # Custom styling (gradients, timeline, skills)
├── Dockerfile                       # nginx:alpine image serving the site
├── sonar-project.properties         # SonarQube scan config
├── README.md                        # This file
├── SECRETS.md                       # GitHub secrets needed for the workflows
└── .github/
    └── workflows/
        ├── deploy-without-docker.yml  # CD: rsync to EC2 + reload Nginx
        └── ci-cd.yml                  # CI/CD: Sonar gate → build → Trivy → push
```

## 🔁 Pipeline (`ci-cd.yml`)

```
SonarQube scan ─▶ Quality Gate ─▶ docker build ─▶ Trivy image scan ─▶ docker push
   (source)         (blocks)        (local load)     (blocks on CVE)     (Docker Hub)
```

- **Scan source before building** — if the Quality Gate fails, nothing builds.
- **Build, then scan the image with Trivy** for HIGH/CRITICAL CVEs. The image is
  loaded locally and **only pushed if Trivy passes**, so a vulnerable image never
  reaches Docker Hub.
- On **pull requests** only the SonarQube gate runs (no build/publish).

## 🚀 Deployment

On every push to `main` (or a manual trigger), GitHub Actions:

1. `rsync`s `index.html` and `style.css` to `/var/www/<domain>` on the EC2
   instance over SSH.
2. Reloads Nginx.

Nginx installation and the SSL certificate are handled by your server-side setup
scripts — the workflow only deploys the static files.

### Setup

1. Configure the repository secrets listed in **[SECRETS.md](SECRETS.md)**.
2. Run the one-time server preparation steps in that same file.
3. Push to `main` — the workflow does the rest.

## 🐳 Docker

The [`ci-cd.yml`](.github/workflows/ci-cd.yml) pipeline builds the image, scans
it with Trivy, and pushes it to Docker Hub as `<user>/devops-profile` on every
push to `main` (needs `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets).

Run it locally:

```bash
docker build -t devops-profile .
docker run -p 8080:80 devops-profile
# then visit http://localhost:8080
```

## 🛠️ Local preview (no Docker)

It's a static site — just open `index.html` in a browser, or serve it:

```bash
python3 -m http.server 8080
# then visit http://localhost:8080
```

## 🧰 Tech stack

- Bootstrap 5.3 + Bootstrap Icons (via CDN)
- Inter font (Google Fonts)
- Custom CSS
- GitHub Actions · AWS EC2 · Nginx · Let's Encrypt · Docker · Docker Hub · SonarQube
