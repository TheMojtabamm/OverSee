# Oversea gate (oversee) — optional container image.
#   docker build -t oversee ./server
#   docker run -d --name oversee --restart unless-stopped --network host \
#     -v /etc/oversea:/etc/oversea oversee gate
# --network host lets it reach Xray on 127.0.0.1 and bind :80/:443 for Let's Encrypt.
# NOT TESTED in CI yet. The systemd install (install.sh) is the primary path; it runs
# unprivileged with CAP_NET_BIND_SERVICE.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/oversee ./cmd/oversee

# Runs as root inside the container so it can bind :80/:443 (a non-root user would need
# extra capability plumbing under --network host). It writes only to /etc/oversea.
FROM gcr.io/distroless/static-debian12
COPY --from=build /out/oversee /usr/local/bin/oversee
ENTRYPOINT ["/usr/local/bin/oversee"]
CMD ["gate"]
