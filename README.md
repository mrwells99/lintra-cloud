# Lintra.cloud

A production-ready managed IT service platform built on open-source infrastructure. Designed as a full alternative to Microsoft 365 + traditional MSP stacks for small businesses — with a focus on data sovereignty, zero vendor lock-in, and predictable costs.

Each client gets a dedicated, isolated cloud environment. No shared tenants, no shared risk.

---

## The Problem This Solves

Small businesses are stuck between expensive Microsoft-dependent MSPs that create vendor lock-in and licensing complexity, or doing nothing and accepting the security risk. Traditional MSPs often resell the same Microsoft stack at a markup with little differentiation.

Lintra replaces the Microsoft stack with open-source equivalents deployed on dedicated per-client cloud infrastructure — giving businesses enterprise-grade security and functionality without enterprise licensing costs. For businesses in regulated industries like healthcare, finance, or legal, the platform is architected to meet compliance requirements including HIPAA out of the box.

---

## Architecture

Each client runs on a dedicated DigitalOcean droplet. No shared infrastructure between clients. All services are containerized via Docker and Docker Compose, connected over a Tailscale private network with a Caddy reverse proxy handling internal TLS termination via a self-managed PKI.

```
Client Droplet (DigitalOcean)
├── Caddy              — Reverse proxy + internal TLS (custom CA)
├── Nextcloud          — File storage and collaboration (replaces SharePoint/OneDrive)
├── OnlyOffice         — In-browser document editing (replaces Office 365)
├── Keycloak           — SSO / OIDC identity provider (replaces Entra ID)
├── 389ds              — LDAP directory server (replaces Active Directory)
├── Vaultwarden        — Password manager (self-hosted Bitwarden)
├── Wazuh              — SIEM, endpoint monitoring, ClamAV alerting
└── Uptime Kuma        — Service health monitoring

Management Server (separate droplet)
├── MeshCentral        — Remote desktop and endpoint support
└── FleetDM            — Endpoint management and osquery telemetry

Client Workstations
└── Fedora (KDE) — enrolled via enroll.sh
```

**Networking:** All services are Tailscale-only. DigitalOcean firewall rules block all public traffic — there is no public attack surface. Clients reach their services via internal `.lintra` hostnames that resolve only over the Tailscale mesh.

---

## Service Stack

| Service | Role | Replaces |
|---|---|---|
| Nextcloud | File storage, sync, sharing | OneDrive / SharePoint |
| OnlyOffice | Document editing | Microsoft Office / 365 |
| Keycloak | SSO, OIDC, MFA | Entra ID / Azure AD |
| 389ds (LDAP) | Directory, user/group management | Active Directory |
| Vaultwarden | Password management | — |
| Wazuh | SIEM, threat detection, compliance logging | Microsoft Defender / Sentinel |
| MeshCentral | Remote support, remote desktop | TeamViewer / Intune remote |
| FleetDM | Endpoint inventory, osquery telemetry | Intune |
| Uptime Kuma | Uptime monitoring and alerting | — |
| Caddy | Reverse proxy, TLS termination | — |
| Tailscale | Private network backbone | VPN / DirectAccess |

---

## Compliance & Security Design

**Data sovereignty:** Client data never leaves their dedicated droplet unencrypted. Each client's environment is physically isolated at the VM level — no shared databases, no shared storage, no shared network.

**HIPAA-ready architecture:** For clients in regulated industries, the platform is designed to satisfy HIPAA technical safeguard requirements — encrypted data at rest and in transit, access controls via LDAP/SSO, audit logging via Wazuh, and minimum necessary access enforcement through RBAC in Keycloak.

**Cloud storage without BAA complexity:** Nextcloud encrypts files server-side before upload to Backblaze B2. The storage provider never handles plaintext data, eliminating BAA requirements with the storage tier while keeping costs low.

**Zero public exposure:** All services bind to Tailscale interfaces only. The DigitalOcean firewall drops everything that isn't Tailscale traffic. There is no publicly reachable attack surface.

**Internal PKI:** Caddy operates as an internal certificate authority. All `.lintra` services use TLS with certs issued by the Lintra root CA, pushed to client workstations during enrollment. No self-signed cert warnings, no Let's Encrypt dependency for internal services.

**Audit logging:** Wazuh aggregates logs from all endpoints and services. Custom detection rules surface failed auth attempts, ClamAV scan results, privilege escalation, and anomalous SSH activity.

---

## Workstation Enrollment

Client workstations run Fedora with KDE, deployed via [`enroll.sh`](./enroll.sh) — a fully automated Bash enrollment script distributed on an encrypted USB drive.

### What enroll.sh does:

- Decrypts credentials from an AES-256-CBC encrypted `.env` file on the USB drive
- Sets hostname, timezone, and NTP sync
- Installs and configures the full X11/KDE/SDDM stack forced to X11 (required for MeshCentral remote desktop)
- Connects the workstation to the Tailscale private network
- Configures SSSD for LDAP authentication against 389ds — users log in with their directory credentials
- Installs the Lintra root CA and MeshCentral CA into the system trust store
- Installs and configures the MeshCentral remote support agent
- Installs and configures the FleetDM/osquery endpoint agent
- Deploys the Nextcloud desktop client with systemd user service autostart
- Configures Firefox with managed bookmarks and policies via `policies.json`
- Hardens SSH: key-only auth, root login disabled, `AllowUsers lintra` only
- Configures ClamAV with a weekly systemd scan timer
- Auto-detects TPM and enrolls LUKS disk encryption key to TPM2 for passwordless secure boot
- Disables KDE Wallet, first-login welcome screens, and Wayland sessions
- Applies branding assets (wallpaper, lock screen) from USB

A single USB drive, a single password prompt, and the workstation is fully enrolled, domain-joined, and production-ready in under 10 minutes.

---

## Repository Structure

```
lintra-cloud/
├── enroll.sh                        # Workstation enrollment script
├── services/
│   ├── 389ds/
│   │   └── docker-compose.yml       # LDAP directory server
│   ├── caddy/
│   │   ├── docker-compose.yml       # Reverse proxy
│   │   └── Caddyfile                # Virtual host config + PKI
│   ├── nextcloud/
│   │   └── docker-compose.yml       # File storage + Redis + MariaDB
│   ├── onlyoffice/
│   │   └── docker-compose.yml       # Document editing server
│   ├── uptime-kuma/
│   │   └── docker-compose.yml       # Monitoring
│   └── wazuh/
│       └── docker-compose.yml       # SIEM stack (indexer + manager + dashboard)
```

---

## Deployment Model

1. Provision a DigitalOcean droplet for the client
2. Connect it to the Tailscale network and apply firewall rules
3. Clone this repo and deploy services with `docker compose up -d` per service directory
4. Issue user accounts in 389ds, configure Keycloak realm and OIDC clients
5. Enroll client workstations via USB + `enroll.sh`

Each service directory is self-contained with its own `docker-compose.yml`. Services communicate over a shared Docker bridge network (`lintra`) and are exposed only through Caddy on the Tailscale interface.

---

## Status

Platform is fully built and operational. Architecture is designed to be reproduced per-client with minimal manual steps — moving toward Ansible-based provisioning for full infrastructure-as-code deployment.

---

## Tech Stack Summary

`Docker` `Docker Compose` `Bash` `Tailscale` `Caddy` `Keycloak` `389ds (LDAP)` `Nextcloud` `Wazuh` `FleetDM` `MeshCentral` `Fedora/RHEL` `systemd` `SELinux` `TPM2` `LUKS` `OpenSSL` `DigitalOcean` `Backblaze B2`
