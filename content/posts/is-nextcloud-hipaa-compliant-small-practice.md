---
title: "Is Nextcloud HIPAA-compliant for a small practice?"
slug: "is-nextcloud-hipaa-compliant-small-practice"
date: 2026-08-05
description: "The honest answer, the configuration that actually satisfies the Security Rule, and the Business Associate Agreement problem that most self-hosting guides get backwards."
tags: ["HIPAA", "Nextcloud", "self-hosting"]
---

If you run a small behavioral health or psychiatric practice and you've started
looking at what it would cost to keep paying Microsoft or Google forever, you
have probably found Nextcloud. It does what you need — files, sharing, document
editing, calendars, desktop and mobile sync — and it's free.

Then you hit the question that stops everything: *can I legally put patient
records in it?*

The short answer is yes, and I'll show you the configuration. But there's a
specific piece that nearly every self-hosting guide gets backwards, and it's the
piece that would actually hurt you in an audit. That's most of what this post is
about.

## The framing problem

Nextcloud is not HIPAA-compliant. Neither is Microsoft 365, Google Workspace,
Dropbox, or any other product. **Software cannot be HIPAA-compliant, because
HIPAA regulates organisations, not software.**

This sounds like pedantry. It isn't — it's the difference between two very
different questions:

- *"Is this software compliant?"* → a shopping question, answered by a vendor's
  marketing page.
- *"Does my practice's use of this software satisfy the Security Rule, and are
  my agreements in place?"* → the actual question, answered by your
  configuration and your paperwork.

A vendor claiming their product "is HIPAA-compliant" is either being loose with
language or hoping you don't know the difference. What a vendor can honestly
offer is a product that *can be configured* to support your compliance, plus a
Business Associate Agreement. Everything else is on you.

So the real question is: **can Nextcloud be configured to meet the Security
Rule's requirements, and can the rest of the stack it sits on be brought under
proper agreements?** Yes to both. Here's what that takes.

## What the Security Rule actually asks for

Strip away the jargon and the technical safeguards come down to five things you
have to be able to demonstrate:

1. **Access control** — each person has a unique identity, and can reach only
   what they need.
2. **Audit controls** — you can reconstruct who did what, and when.
3. **Integrity** — you can show records haven't been improperly altered or
   destroyed.
4. **Authentication** — you can prove people are who they claim to be.
5. **Transmission security** — PHI is protected in transit.

Encryption at rest sits slightly apart. It's *addressable* rather than
*required*, which does not mean optional — it means you either implement it or
document a written justification for why you didn't and what you did instead.
In practice, on a small-practice budget, there is no defensible reason not to
encrypt. Do it and skip the paperwork argument.

## Configuring Nextcloud

### Unique identities, from a directory

Do not create local Nextcloud accounts for staff. It's the fastest path to an
audit finding you can't answer.

The problem is offboarding. When a clinician leaves, you need their access gone
everywhere, immediately, and you need to be able to *prove* it was gone from the
moment it mattered. If identity lives in six separate applications, you're
relying on someone remembering all six, and your evidence is a checklist someone
ticked.

Bind Nextcloud to a directory — LDAP, or an OIDC provider like Keycloak in front
of it — so identity has exactly one home. Disable the account in one place and
it's disabled everywhere, with a log entry proving when.

```bash
# Nextcloud reads users from LDAP; it never stores their passwords.
occ app:enable user_ldap
occ ldap:create-empty-config
occ ldap:set-config s01 ldapHost "ldaps://ldap.internal"
occ ldap:set-config s01 ldapPort 636
occ ldap:set-config s01 ldapBase "dc=practice,dc=internal"
occ ldap:set-config s01 ldapUserFilter "(&(objectClass=inetOrgPerson)(memberOf=cn=clinical,ou=groups,dc=practice,dc=internal))"
occ ldap:set-config s01 turnOnPasswordChange 0
```

That `ldapUserFilter` is doing real work. Only members of the group you name can
authenticate at all — so directory membership *is* your access control, and
"minimum necessary" becomes a group membership decision rather than a
per-application one.

Then turn off the ways around it:

```bash
occ config:system:set auth.webauthn.enabled --value=false --type=boolean
occ user:setting admin core lang en    # keep the break-glass local admin, and
                                       # only that one, with a long stored secret
```

Keep exactly one local administrator for the case where the directory is
unreachable. Its password lives in your password manager, it is not a person's
day-to-day account, and its use should be rare enough that you notice it in the
logs.

### Enforce MFA, and check that it's enforced

Enabling the two-factor app is not the same as requiring it. Enable, then
enforce, then verify:

```bash
occ app:enable twofactor_totp
occ config:app:set twofactor_enforced enforced --value enabled
occ config:app:set twofactor_enforced enforced_groups --value '["clinical","admin"]'

# Verify — this is the part people skip
occ twofactor:state alice
```

If that last command doesn't show enforcement, it isn't enforced, whatever the
admin UI implies.

### Sharing defaults, which are wrong out of the box

Nextcloud ships with defaults tuned for a general audience, and several of them
are actively wrong for PHI. Public link sharing in particular creates
unauthenticated URLs — anyone who has the link has the file, forever, with no
identity attached to the access. That's a disclosure you cannot audit.

```bash
occ config:app:set core shareapi_allow_links --value=no
occ config:app:set core shareapi_allow_public_upload --value=no
occ config:app:set core shareapi_default_expire_date --value=yes
occ config:app:set core shareapi_expire_after_n_days --value=7
occ config:app:set core shareapi_enforce_expire_date --value=yes
occ config:app:set core shareapi_allow_resharing --value=no
occ config:app:set files_sharing outgoing_server2server_share_enabled --value=no
```

If your workflow genuinely needs external sharing — sending records to another
provider, say — turn links back on but keep enforced expiry and mandatory
passwords. Don't leave them on "just in case." The default state should be that
PHI cannot leave the system without an authenticated identity attached to it.

### Server-side encryption, and what it's actually for

```bash
occ app:enable encryption
occ encryption:enable
occ encryption:enable-master-key
```

Be clear-eyed about what this buys you. Server-side encryption protects data
where it's *stored* — external object storage, backup targets, a stolen disk.
It does **not** protect against a compromise of the running Nextcloud server
itself, because a running server necessarily holds the keys to serve files to
logged-in users.

That's still worth having. It's the difference between a lost backup tape being
a non-event and being a reportable breach. Just don't let it stand in for the
access controls that do the real work — and, as we're about to get to, don't let
anyone tell you it removes a legal obligation.

### Audit logging that survives the server

```bash
occ app:enable admin_audit
occ config:app:set admin_audit logfile --value "/var/log/nextcloud/audit.log"
occ config:system:set log_type --value=file
occ config:system:set loglevel --value=1
```

Then ship those logs somewhere the Nextcloud server cannot write to. An audit
log that lives only on the box being audited is worth very little — anyone who
compromises the server can edit it, and you can't prove they didn't. Forward to
a separate log host or SIEM. I use Wazuh for this; rsyslog to a different
machine is fine too. What matters is that the copy of record lives somewhere the
application can't reach.

Keep six years. That's the HIPAA documentation retention period, and it will be
longer than you expect to need it.

### Transport

TLS everywhere, including internally. The old habit of running plaintext HTTP
"inside the trusted network" doesn't survive contact with the Security Rule, and
there's no longer a good reason for it — a reverse proxy with an internal CA
handles this in a few lines.

Better still, don't expose the thing publicly at all. On the deployments I run,
Nextcloud has no public address: it binds to a private mesh network, the cloud
firewall drops everything else, and staff reach it over that mesh from wherever
they are. An attacker cannot brute-force a login page they cannot route to. This
is a bigger security win than most of the configuration above, and it costs
essentially nothing.

## Now the part that everyone gets wrong

Here's the setup. You've done everything above. Nextcloud is locked down, MFA is
enforced, links are off, encryption is on, logs ship offsite. You're running it
on a rented server — DigitalOcean, Hetzner, Vultr — with backups going to
object storage like Backblaze B2.

Nextcloud encrypts files before they reach that object storage. The storage
provider only ever holds ciphertext and never has the key. So — no PHI is
exposed to them, and no Business Associate Agreement is needed with the storage
provider, right?

**No.** And this is the single most repeated error in self-hosted HIPAA guides.

HHS's Office for Civil Rights addressed this directly in its
[guidance on HIPAA and cloud computing](https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html).
A cloud service provider that creates, receives, maintains, or transmits ePHI on
behalf of a covered entity **is a business associate — even if the ePHI is
encrypted and the provider has no decryption key.**

OCR uses the term "no-view services" for exactly this arrangement, and it is
explicit that no-view status does not exempt anyone. What it changes is the
*allocation* of responsibility: with no-view services, some Security Rule
obligations may be satisfied by one party rather than both — you handle
authentication and who can see what, the provider handles safeguards on the
storage layer. It changes *who does what*. It does not change whether a BAA is
required.

The reasoning holds up when you think about it. Confidentiality is one of three
properties the Security Rule protects. Encryption addresses confidentiality — it
does nothing for **availability** or **integrity**. If your storage provider
loses your encrypted backups, or silently corrupts them, you have a HIPAA
problem that no amount of encryption prevented. The BAA is what contractually
obligates them on those points and makes them directly liable.

### This applies to your server host, and there it's worse

If encrypted-at-rest storage needs a BAA, then your compute provider certainly
does. The droplet or VM running Nextcloud holds PHI **in plaintext** — in
memory, in the database, and on disk while the service is running. That provider
is unambiguously a business associate.

This is where a lot of otherwise-careful self-hosted setups have a hole in them:
the practice signed nothing with the company that owns the physical machine
their patient records live on.

The good news is that the major providers will sign. As of this writing:

- **DigitalOcean** offers a BAA through its trust centre. It comes with real
  conditions: ePHI is restricted to specifically designated Covered Products,
  and the BAA requires a paid Standard or Premium support plan. That support
  requirement is a genuine recurring cost — budget for it rather than
  discovering it later.
- **Backblaze** provides a BAA on request for business customers.

Terms, covered-product lists, and plan requirements all change. Confirm the
current version directly with each provider rather than trusting a blog post —
including this one.

### The checklist that actually matters

Every entity that touches PHI on your behalf needs a signed BAA in place
*before* any PHI reaches the system:

- [ ] Compute/hosting provider — the server itself
- [ ] Object storage / backup provider
- [ ] Any managed database or managed email service in the path
- [ ] Any monitoring or log aggregation service that could ingest PHI
- [ ] Your IT provider — me, if that's the arrangement, or whoever else
- [ ] Anyone else with administrative access to the environment

Two things worth flagging on that list. Monitoring and logging services get
overlooked constantly, and they routinely ingest filenames, usernames, and error
messages containing patient identifiers — that's PHI sitting in a third-party
SaaS nobody signed anything with. And self-hosting doesn't eliminate business
associates; it *reduces* them. Going from Microsoft-plus-an-MSP down to a host
and a storage provider is a real reduction in third-party exposure. But two is
not zero, and it's the two you now have to actually paper.

## So what does "getting it right" involve?

Reading back over this: the Nextcloud configuration is maybe two hours of work
for someone who's done it before, and every command is above.

The hard parts aren't the commands.

The hard part is knowing that `shareapi_allow_links` defaults to yes and that
this matters. That enabling the 2FA app doesn't enforce it. That an audit log on
the audited machine isn't evidence. That encryption doesn't remove a BAA
obligation — the specific thing this whole post exists to correct, and something
I have watched competent technical people get wrong repeatedly.

And then the part that never ends: patching Nextcloud when a CVE lands,
verifying backups actually restore rather than assuming, noticing the
certificate expiring in nine days, re-checking the sharing defaults after a major
upgrade quietly resets one, and keeping the six-year documentation trail current
so that if OCR ever asks, the answer is a folder rather than a scramble.

Any competent technical person can build this. The question is whether you want
to be the person who's responsible when a setting drifts and nobody notices for
eight months.

If you want to build it yourself, everything you need is above — genuinely, go
do it, and email me if you get stuck on something. I'd rather more practices
were running this properly than not.
