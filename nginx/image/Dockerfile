# Official nginx + every Alpine security fix available at build time.
# The upstream image is rebuilt rarely, so fixes in Alpine (libxml2, libxslt,
# openssl, ...) would otherwise wait weeks. Rebuilt on every infra deploy and
# weekly by the scheduled run of .github/workflows/deploy.yml.
FROM nginx:1.31.9-alpine
# Changes on every build (006-deploy-infra.sh), so the build cache never hides a fix.
ARG SECURITY_REFRESH=0
RUN apk upgrade --no-cache
