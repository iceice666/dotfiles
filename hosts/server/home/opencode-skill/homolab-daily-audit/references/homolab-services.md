# Homolab Services

Use this file to map service names and log slices in the audit bundle back to their intended role on `homolab`.

## Host Identity

- Host name: `homolab`
- Time zone: `Asia/Taipei`
- Primary admin user: `iceice666`

## Internet-Facing Services

- `sshd.service`
  - SSH is enabled on port `2222`
  - `PermitRootLogin = no`
  - `PasswordAuthentication = false`
  - `AllowUsers = [ iceice666 ]`
- `cloudflared-tunnel.service`
  - Maintains the Cloudflare tunnel for public ingress
- `traefik.service`
  - Terminates TLS and routes traffic for public services
- `authelia-main.service`
  - Handles identity, SSO, and forward-auth checks
- `forgejo.service`
  - Serves `code.justaslime.dev`
- `woodpecker-server.service`
  - Serves `ci.justaslime.dev`

## Protected Or Internal Services

- `dynacat.service`
  - Dashboard behind Authelia at `home.justaslime.dev`
- `woodpecker-agent-docker.service`
  - CI worker using Docker
- `docker.service`
  - Container runtime
- `postgresql.service`
  - Backing database for server applications
- `rustfs.service`
  - Object storage used by Forgejo LFS
- `dnsmasq.service`
  - Local DNS and resolver support
- `cloudflare-ips-refresh.service`
  - Refreshes trusted Cloudflare IP sets daily
- `cloudflare-dyndns.service`
  - Updates Cloudflare DNS records

## Expected Access Patterns

- SSH activity should center on the `iceice666` account.
- Root SSH logins should never succeed.
- Password-based SSH auth should never succeed because password authentication is disabled.
- `home.justaslime.dev` should normally require Authelia two-factor auth.
- Public ingress noise against `traefik`, `cloudflared-tunnel`, and `sshd` is expected; treat it as suspicious only when it leads to successful access, privilege change, or service degradation.
