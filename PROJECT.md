# Lintra.cloud — Website & Blog Build Brief

A build spec for Claude Code. The strategy below is already decided — build against it, don't re-litigate it. Ask before deviating from the stack or page structure.

## What this is

Lintra.cloud is a HIPAA-compliant, open-source managed IT service for small behavioral health and psychiatric practices — data sovereignty without Microsoft or Google lock-in. This project turns the existing lintra.cloud site into a **content-led front door**: a technical blog that builds trust through demonstrated expertise, with the service offering kept understated in the background.

The blog is the engine. Every other part of the site exists to support it and to catch a reader the moment they decide they'd rather hire than DIY. There is no hard sell anywhere.

## Who it's for

- **Primary buyer:** owners/managers of small behavioral health & psychiatric practices who care about real HIPAA compliance and not being locked into big-vendor ecosystems.
- **Secondary:** technical peers (other MSP / self-hosted / homelab people) who find the writing via search and communities — they amplify reach and reinforce credibility.
- The operator's expertise *is* the trust signal, so the writing and the About page carry more weight than any marketing copy.

## Stack & hosting

- **Static site on GitHub Pages** — already hosting lintra.cloud with the custom domain configured. Preserve the existing domain / CNAME setup.
- **Recommended generator: Hugo.** Single binary, no `node_modules`, fastest path for a pure content/blog site, first-class GitHub Pages deploy via GitHub Actions, large theme ecosystem, writes in Markdown. Chosen deliberately to keep this infra/content, not frontend maintenance.
  - *Alternative:* Astro, only if more design/component flexibility is wanted later. Default to Hugo unless there's a specific reason not to.
- **Check the existing repo first.** The current site may be hand-written HTML. If so, migrate its content into the Hugo structure rather than bolting a blog onto raw HTML. Posts are Markdown — never hand-author post HTML.
- **No backend.** GitHub Pages is static, so contact is a plain email / `mailto:` link, not a server-side form. (A third-party form service is an optional later add; email is lower-friction for this volume.)
- Deploy via GitHub Actions building Hugo → Pages. HTTPS + custom domain already work.

## Design & tone

- Clean, fast, content-forward, readable. Typography-first, minimal chrome. Should not look like a stock template.
- **Tone: direct and plain. No corporate-speak, no hype, no buzzwords.** Understated competence. The reader should come away thinking "this person clearly knows exactly what they're doing," not "this is a vendor selling me something."
- Long technical posts need to read well — good code-block styling, sensible line length, clear headings. Legibility beats visual flash.

## Site structure

### Home
Short. One clear line on who this is and what Lintra does — e.g. *"HIPAA-compliant, open-source IT for small behavioral health and psychiatric practices. No Microsoft or Google lock-in."* A sentence or two on the philosophy (you own your infrastructure and your data). Then route people into the blog — the writing is the proof. Home orients and sends; it does not sell.

### Blog (the engine)
- Post index (reverse chronological) plus a clean single-post template.
- A visitor should be one click at most from the newest / flagship post.
- Single-post template needs: readable body typography, code-block styling, heading anchors, and the soft CTA footer (see Conversion).

### Services
One page, understated. Describes the offering plainly — the managed open-source stack, HIPAA-compliant setup, ongoing support. Informational, not hyped: the reader arrives already half-sold by the blog, so this page just confirms "yes, he does this professionally, here's the shape of it." No aggressive CTAs.

### About
The operator, specifically — background, the open-source philosophy, why Lintra exists. In this niche the *person* is the credibility, so this page matters more than usual. Plain and real, not a résumé wall.

### Contact
Frictionless and reachable from everywhere. A clear email address (`mailto:`) in the top nav and repeated in the footer of every page. Never make a warm lead hunt for it.

## Conversion (kept quiet)

- `mailto:` in nav + footer on every page.
- At the end of each blog post, one soft line — e.g. *"I set this up for practices professionally. If you'd rather not do it yourself, get in touch."* — placed to catch the reader exactly when they realize they don't want to DIY it.
- **No hard CTAs, banners, popups, or sales language — especially early.** Before reputation exists, a heavy pitch reads as "unknown vendor trying too hard," which is the exact trust problem this approach is built to avoid. Quiet competence converts better here.

## First post — the HIPAA / Nextcloud piece

The first real content. Spec:

- **Frame it as the buyer's worried Google query**, not a generic how-to — e.g. *"Is Nextcloud HIPAA-compliant for a small practice — and how to configure it properly."* That framing is both what ranks (low-competition, high-intent search) and what earns trust when the right person lands on it.
- **Structure:** the worried question → genuine, specific configuration (encryption, access control, the BAA / hosting-provider gotcha, the compliance reasoning) → what "getting it exactly right" actually involves → soft CTA.
- **Put real value on the page.** Show the actual setup and reasoning — that's what proves competence. Let the piece naturally convey how fiddly and consequential correct configuration is, so the reader who thinks "I could do this, but I don't want to be liable if I get it wrong" self-identifies as a customer. Genuine expertise openly shared, not a gated lead magnet.
- Tone as above: plain, precise, no fluff.

## Build order

1. **Skeleton — timeboxed to one sitting.** Hugo up, domain preserved, a clean readable theme, Home + About + Services pages, empty blog index, Actions deploy working. Ugly-but-live beats pretty-but-later. Do not spend three weekends here.
2. Wire the blog: post index + single-post template + CTA footer.
3. Draft and publish post #1 (the Nextcloud piece). This is where the real hours go.
4. Confirm deploy + custom domain + HTTPS.
5. *(Operator, not Claude Code:)* seed the post in one or two relevant communities (r/selfhosted, r/msp) as a genuine contribution.

## Don'ts

- Don't over-engineer the site or perfect the design before any writing exists. Site polish is procrastination that feels like work.
- Don't build a server-backed contact form — email link only.
- Don't add heavy sales copy, popups, or aggressive CTAs, especially early.
- Don't hand-author post HTML — Markdown posts through the generator.
- Don't re-open the strategy in this file — it's settled; build to it.
