---
title: "Services"
description: "Managed open-source IT for small behavioral health practices — the full stack, built on infrastructure dedicated to your practice, run and maintained for you."
---

I build and run the complete IT stack for small practices using open-source
software, on cloud infrastructure dedicated to that practice alone.

It's the same set of things a Microsoft 365 subscription plus a traditional MSP
would give you — file storage, document editing, single sign-on, password
management, security monitoring, remote support, backups — with two differences.
You aren't renting per-seat licences you can never stop paying, and your data
sits on infrastructure you could take custody of tomorrow if you wanted to.

## What's in the stack

| What you get | What it replaces |
|---|---|
| Nextcloud — file storage, sync, sharing | OneDrive / SharePoint |
| OnlyOffice — in-browser document editing | Microsoft Office |
| Keycloak — single sign-on with MFA | Entra ID / Azure AD |
| 389ds — directory and user management | Active Directory |
| Vaultwarden — team password manager | LastPass / 1Password |
| Wazuh — security monitoring and audit logging | Defender / Sentinel |
| MeshCentral — remote support | TeamViewer |
| FleetDM — endpoint inventory | Intune |
| Uptime Kuma — service monitoring and alerting | — |

All of it is real open-source software with real communities behind it. None of
it is something I invented and none of it disappears if I do.

## How it's built

Every practice gets its own dedicated server. Not a shared tenant with logical
separation — a separate machine, with separate storage and a separate database.
One practice's problem cannot become another practice's problem.

Nothing is exposed to the public internet. Services bind only to a private
[Tailscale](https://tailscale.com/) network, and the cloud firewall drops
everything that isn't Tailscale traffic. There is no login page for an attacker
to find, because there is no public address to find it at. Staff reach their
files and documents through that private network from wherever they work.

Data is encrypted in transit and at rest. Access is controlled through the
directory and enforced by single sign-on, so revoking someone's access is one
action in one place rather than six. Wazuh keeps the audit trail — failed
logins, privilege changes, malware scan results — which is the part everybody
forgets until they need it.

Workstations are enrolled from a USB drive with an automated script: directory
login, disk encryption tied to the machine's TPM, security agents, monitoring,
and the file sync client, in about ten minutes per machine.

## About HIPAA

Software is not "HIPAA-compliant." Practices are. Any vendor who tells you their
product *is* HIPAA-compliant is telling you something that isn't a real category,
and it's worth noticing when they do.

What actually matters is whether the configuration satisfies the Security Rule,
and whether every vendor that touches your PHI has signed a Business Associate
Agreement. That includes the ones you don't think of as vendors — the company
renting you the server, and the company storing your backups. Encrypting data
before it reaches them does not remove that obligation. [HHS has been explicit
about this](https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html):
a provider holding encrypted PHI it cannot read is still a business associate and
still needs a BAA.

So that's part of the work. The infrastructure is deployed on providers that
will execute a BAA, on the specific plans and services their BAA actually covers,
with those agreements in place before any PHI touches the system. I'll walk you
through exactly which agreements exist and what each one covers.

I'm also a business associate of your practice, and I sign a BAA with you.

## Ongoing

Setup is the small part. The ongoing work is patching, monitoring, backup
verification, responding when something breaks, onboarding and offboarding
staff, and being reachable when a clinician can't open a file fifteen minutes
before a session.

## What it costs

Engagements are scoped per practice — it depends on headcount, how many
workstations, what you're migrating from, and how much of the compliance
documentation you want handled. I'd rather look at your actual situation and
give you a real number than publish a per-seat price that turns out to be wrong
for you.

[Email me](mailto:mwells@lintra.cloud) and we can work out whether this is a
fit. If it isn't, I'll tell you that too.
