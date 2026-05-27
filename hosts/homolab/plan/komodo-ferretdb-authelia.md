# Komodo + FerretDB + Authelia Deployment Plan

## Goal

Deploy Komodo on `homolab` using:

- FerretDB backed by its dedicated `postgres-documentdb` container
- Authelia OIDC login at `https://komodo.justaslime.dev`
- Podman socket access scoped only to the Komodo periphery service

This plan is for a repo-native NixOS deployment that matches the existing service patterns in this flake.

## Fixed Decisions

- External hostname: `komodo.justaslime.dev`
- Keep local Komodo username/password auth only for initial bootstrap
- Persistent runtime data should live under `/var/lib`, not `/mnt/storage`
- Secret material should be introduced as placeholders and wired through SOPS-managed paths later

## Target Architecture

- `komodo-core` runs as a Podman OCI container.
- `ferretdb` runs as a Podman OCI container.
- `postgres-documentdb` runs as a Podman OCI container dedicated only to FerretDB.
- `komodo-periphery` runs as a host `systemd` service, not a container.
- Traefik exposes Komodo at `komodo.justaslime.dev` using a private host rule.
- Komodo handles its own OIDC login against Authelia.
- Traefik should not apply `authelia@file` middleware to the Komodo route.
- Podman socket access is granted only to the Komodo periphery service account via membership in the `podman` group.

## Why This Direction

- It matches the repo's existing `virtualisation.oci-containers` pattern for containerized services.
- It matches the existing dedicated-service-user pattern for Podman socket consumers already used by Woodpecker.
- It avoids reusing the host PostgreSQL service, which is tightly scoped and not a good fit for FerretDB v2.
- It avoids the extra mount and socket complexity of running Komodo periphery in a container on the same host.
- It keeps Komodo behind Traefik while letting Komodo own the OIDC callback flow directly.

## Service Layout

### Komodo Core

- Image: `ghcr.io/moghtech/komodo-core:2`
- Bind only to loopback, for example `127.0.0.1:<komodo-port>:9120`
- Join the same Podman network as FerretDB and `postgres-documentdb`
- Use environment variables for host URL, DB address, OIDC, and bootstrap auth

Core configuration targets:

- `KOMODO_HOST=https://komodo.justaslime.dev`
- `KOMODO_DATABASE_ADDRESS=ferretdb:27017`
- `KOMODO_OIDC_ENABLED=true`
- `KOMODO_OIDC_PROVIDER=https://auth.justaslime.dev`
- `KOMODO_OIDC_CLIENT_ID=komodo`
- `KOMODO_OIDC_CLIENT_SECRET=<from secret file>`
- `KOMODO_LOCAL_AUTH=true` during bootstrap only
- `KOMODO_INIT_ADMIN_USERNAME=<from secret file>`
- `KOMODO_INIT_ADMIN_PASSWORD=<from secret file>`

### FerretDB

- Image: `ghcr.io/ferretdb/ferretdb`
- Internal-only on the shared Podman network
- No host port publication required
- Connect to the dedicated `postgres-documentdb` container

### Postgres DocumentDB Backend

- Image: `ghcr.io/ferretdb/postgres-documentdb`
- Dedicated only to FerretDB
- Internal-only on the shared Podman network
- No host port publication required

### Komodo Periphery

- Run as a host `systemd` service
- Use a dedicated system user such as `komodo-periphery`
- Add `extraGroups = [ "podman" ]`
- Set `DOCKER_HOST=unix:///run/podman/podman.sock`
- Use outbound mode to connect back to Komodo Core
- Persist its root directory under `/var/lib/komodo/periphery`

This is the intended way to expose the Podman socket to Komodo without broadening host runtime access.

## Files Expected To Change

- `lib/homolab.nix`
- `services/dev/default.nix`
- `services/dev/komodo.nix`
- `services/edge/traefik.nix`
- `services/edge/authelia.nix`
- `configuration/networking.nix`
- `configuration/sensitive/edge.nix`
- `sensitive/authelia.yaml`
- likely a new Komodo-specific SOPS file or new entries in an existing secrets file

## Shared Constants To Add

Add new constants in `lib/homolab.nix` for:

- `urls.komodo = "https://komodo.justaslime.dev"`
- `domains.komodo = "komodo.justaslime.dev"` or the repo's equivalent host/domain split
- a new loopback-only service port for Komodo Core

The new port should then be consumed by Traefik and added to loopback drop rules in `configuration/networking.nix`.

## Storage Layout Under `/var/lib`

Suggested host paths:

- `/var/lib/komodo/core`
- `/var/lib/komodo/keys`
- `/var/lib/komodo/periphery`
- `/var/lib/ferretdb`
- `/var/lib/postgres-documentdb`

Suggested use:

- `komodo-core` container state: `/var/lib/komodo/core`
- shared trust/key material between Core and Periphery: `/var/lib/komodo/keys`
- Periphery root directory: `/var/lib/komodo/periphery`
- FerretDB data if needed by image layout: `/var/lib/ferretdb`
- Postgres DocumentDB data directory: `/var/lib/postgres-documentdb`

## Authelia OIDC Design

Komodo should use Authelia as a standard OIDC provider, not Traefik forward-auth.

Add `identity_providers.oidc` to `services/edge/authelia.nix` with:

- provider `hmac_secret`
- at least one RSA JWK for signing with `RS256`
- Komodo client registration

Komodo client shape should follow the Authelia Komodo integration guidance:

- `client_id: "komodo"`
- `client_name: "Komodo"`
- `public: false`
- `require_pkce: true`
- `pkce_challenge_method: "S256"`
- `authorization_policy: "two_factor"`
- `redirect_uris: [ "https://komodo.justaslime.dev/auth/oidc/callback" ]`
- `scopes: [ "openid", "profile", "email" ]`
- `response_types: [ "code" ]`
- `grant_types: [ "authorization_code" ]`
- `access_token_signed_response_alg: "none"`
- `userinfo_signed_response_alg: "none"`
- `token_endpoint_auth_method: "client_secret_basic"`

## Secret Placeholders To Introduce

### Authelia Provider Secrets

Add placeholder-backed SOPS entries for:

- `oidcHmacSecret`
- `oidcJwkRsaKey`
- `komodoOidcClientSecretHash`

Notes:

- `oidcHmacSecret` is the provider-level HMAC secret required by Authelia OIDC.
- `oidcJwkRsaKey` should be a PEM-encoded RSA private key used for JWK signing.
- `komodoOidcClientSecretHash` should be the hashed form stored in the Authelia client config.

### Komodo Runtime Secrets

Add placeholder-backed secrets for:

- `komodoOidcClientSecret`
- `komodoBootstrapAdminUsername`
- `komodoBootstrapAdminPassword`

Notes:

- `komodoOidcClientSecret` is the plaintext secret consumed by Komodo Core.
- `komodoBootstrapAdminUsername` and `komodoBootstrapAdminPassword` are temporary bootstrap credentials.
- After first successful admin onboarding, the local auth bootstrap path should be removed or disabled.

## Podman Network Design

Create a shared Podman network for the three containers or attach them to a common existing network with stable aliases.

Required service discovery assumptions:

- `postgres` resolves to the DocumentDB backend container
- `ferretdb` resolves to the FerretDB container

This keeps `KOMODO_DATABASE_ADDRESS=ferretdb:27017` aligned with upstream expectations.

## Traefik Routing Design

Add a new Traefik router and service for Komodo:

- rule should match `komodo.justaslime.dev`
- use the repo's private-host rule helper
- forward to the Komodo Core loopback port
- do not apply `authelia@file`

Rationale:

- Komodo needs to manage its own OIDC redirects and callback path.
- Wrapping it in forward-auth would create redundant auth and may break callback flow.

## Firewall And Local Exposure

The Komodo Core port should be treated like the other loopback-only admin services:

- bind Core only to `127.0.0.1`
- add the port to explicit loopback-only drop rules in `configuration/networking.nix`
- expose only through Traefik on approved LAN and Tailscale paths

## Bootstrap Flow

1. Deploy Komodo Core with local auth enabled and OIDC enabled.
2. Log in with the bootstrap local admin.
3. Complete initial setup and verify OIDC login against Authelia.
4. Log in through Authelia OIDC.
5. Promote the intended OIDC-backed user to the correct admin role if Komodo does not do that automatically.
6. Remove or disable the bootstrap local auth credentials.

## Recommended Implementation Order

1. Add `lib/homolab.nix` constants for Komodo hostname and port.
2. Add `services/dev/komodo.nix` and import it from `services/dev/default.nix`.
3. Define the three OCI containers and their persistent directories under `/var/lib`.
4. Define the `komodo-periphery` system user and `systemd` service with Podman group access.
5. Add Traefik routing for `komodo.justaslime.dev`.
6. Extend Authelia with OIDC provider configuration and Komodo client registration.
7. Add placeholder SOPS entries and templates for all new secrets.
8. Add the Komodo loopback port to `configuration/networking.nix` protections.
9. Run formatting, checks, and a dry build.

## Validation Checklist

- `komodo-core` starts and binds only on loopback.
- `ferretdb` can reach `postgres-documentdb`.
- `komodo-core` can reach `ferretdb` by container hostname.
- Traefik serves `https://komodo.justaslime.dev`.
- Komodo OIDC redirects to `https://auth.justaslime.dev` correctly.
- Authelia accepts the Komodo client and returns to `/auth/oidc/callback` successfully.
- `komodo-periphery` can access `unix:///run/podman/podman.sock` without `sudo`.
- Komodo can discover and use the local periphery.
- Bootstrap local admin works initially.
- Bootstrap local auth can be removed cleanly after OIDC admin onboarding.

## Risks And Caveats

- The Komodo Core container must be able to reach `https://auth.justaslime.dev` for OIDC discovery and token exchange.
- If host DNS or hairpin routing behaves differently inside the Podman network, an internal reachability adjustment may be required.
- Authelia OIDC enablement is larger than a single client entry because it introduces provider-level signing material.
- Komodo image defaults may shift over time, so pinned image tags should be reviewed before rollout.

## Recommendation Summary

Implement Komodo as a new `services/dev/komodo.nix` module using three Podman containers for Core, FerretDB, and `postgres-documentdb`, plus a host `systemd` Komodo periphery service with tightly scoped Podman socket access.

Expose the UI at `https://komodo.justaslime.dev` through Traefik without forward-auth, and let Komodo authenticate directly against Authelia OIDC using new placeholder-backed provider and client secrets.
