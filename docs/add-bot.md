# Add a new bot

This is the normal lifecycle for a new bot.

## 1. Prepare bot repository

Your bot service must connect to the external `edge` network and expose an internal HTTP port.

Example:

```yaml
services:
  app:
    image: my-bot-image:latest
    restart: unless-stopped
    expose:
      - "8080"
    networks:
      edge:
        aliases:
          - bot1-app

networks:
  edge:
    external: true
    name: edge
```

## 2. Generate a secret static prefix if needed

```bash
./scripts/gen-secret.sh
```

Example result:

```text
4f9e8c2d7b6a1e0f3c9b8a7d6e5f4a3b9c8d7e6f5a4b3c2
```

## 3. Add HTTP site

Without secret static files:

```bash
./scripts/add-site.sh bot1 bot1-203-0-113-10.nip.io bot1-app 8080
```

With secret static files:

```bash
./scripts/add-site.sh bot1 bot1-203-0-113-10.nip.io bot1-app 8080 4f9e8c2d7b6a1e0f3c9b8a7d6e5f4a3b bot1
```

The last parameter `bot1` defines the subdirectory under `data/bot-static/`.

## 4. Reload Nginx

```bash
./scripts/reload-nginx.sh
```

## 5. Issue certificate

```bash
./scripts/issue-cert.sh bot1-203-0-113-10.nip.io you@example.com
```

## 6. Switch site to HTTPS

```bash
./scripts/enable-https.sh bot1 bot1-203-0-113-10.nip.io bot1-app 8080 4f9e8c2d7b6a1e0f3c9b8a7d6e5f4a3b bot1
./scripts/reload-nginx.sh
```

## 7. Static files URL

If secret static files are enabled, files from `data/bot-static/bot1/` are available under:

```text
https://bot1-203-0-113-10.nip.io/__static_<secret>/
```

Example:

```text
https://bot1-203-0-113-10.nip.io/__static_4f9e8c2d7b6a1e0f3c9b8a7d6e5f4a3b__/image.png
```

Important: this is only an unguessable URL, not real authorization.
