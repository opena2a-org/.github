<div align="center">

# OpenA2A

**The standard for AI agent security**

[Website](https://opena2a.org) · [OASB Benchmark](https://oasb.ai) · [Registry](https://registry.opena2a.org) (April 2026) · [Discord](https://discord.gg/uRZa3KXgEn)

</div>

---

Open-source security infrastructure for AI agents. Identity management, runtime protection, security scanning, compliance benchmarks, behavioral governance, and credential management. Apache-2.0, self-hostable, works independently or together.

## Start Here

```bash
npx opena2a-cli review
```

One command scans your project for shadow AI, credentials, config integrity, and governance gaps. Opens an HTML dashboard with a security score.

## Tools

| Tool | What it does | Try it |
|------|-------------|--------|
| **[opena2a-cli](https://github.com/opena2a-org/opena2a)** | Unified CLI — shadow AI detection, identity, governance, scanning, protection | `npx opena2a-cli review` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | 163 security checks, 55 attack payloads, CVE detection, auto-fix | `npx hackmyagent secure` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Keep secrets out of AI tools — Claude Code, Cursor, Copilot, Windsurf | `npx secretless-ai init` |
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Cryptographic identity, capability policies, audit logging, trust scoring | `opena2a identity create` |
| **[AI Browser Guard](https://github.com/opena2a-org/AI-BrowserGuard)** | Detect and control AI agents in the browser | [Chrome Web Store](https://chromewebstore.google.com/detail/ojphpdmabflmcjhglfogmkdgchkncikf) |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Intentionally vulnerable AI agents for security training | `docker compose up` |

## Standards

| Spec | What it defines |
|------|----------------|
| **[OASB-1](https://oasb.ai/oasb-1)** | 46 security controls across 10 categories, 3 maturity levels |
| **[OASB-2](https://oasb.ai/oasb-2)** | Behavioral governance — 72 controls across 9 domains, 4 agent tiers |
| **[OASB Eval](https://oasb.ai/eval)** | 222 attack scenarios for evaluating AI security tools |
| **[ABGS](https://github.com/opena2a-org/agent-governance-spec)** | Agent Behavioral Governance Specification — what goes in SOUL.md |
| **[awesome-agent-souls](https://github.com/opena2a-org/awesome-agent-souls)** | 100+ SOUL.md templates by role, industry, and use case |

## Upstream Contributions

We contribute security fixes back to the projects we audit — not just reports, production code.

**[OpenClaw](https://github.com/openclaw/openclaw)** (205K+ stars) — 8 security PRs, 7 merged:
- Credential redaction in gateway config responses ([#9858](https://github.com/openclaw/openclaw/pull/9858))
- Skill/plugin code safety scanner — 1,721 lines ([#9806](https://github.com/openclaw/openclaw/pull/9806))
- Path traversal prevention in A2UI file serving ([#10525](https://github.com/openclaw/openclaw/pull/10525))
- Timing-safe comparison for hook token auth ([#10527](https://github.com/openclaw/openclaw/pull/10527))
- Supply chain hardening with --ignore-scripts ([#10528](https://github.com/openclaw/openclaw/pull/10528))
- File permission enforcement for credential files ([#10529](https://github.com/openclaw/openclaw/pull/10529))
- Security headers for gateway HTTP responses ([#10526](https://github.com/openclaw/openclaw/pull/10526))
- Skill scanner false positive reduction ([#10530](https://github.com/openclaw/openclaw/pull/10530))

**[Nanobot](https://github.com/HKUDS/nanobot)** — Path traversal, XSS, and shell escape fixes ([#472](https://github.com/HKUDS/nanobot/pull/472))

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              opena2a-cli  (unified entry point)                  │
│              npx opena2a-cli review                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  opena2a detect         → Shadow AI discovery                    │
│  opena2a identity       → AIM  (cryptographic identity)          │
│  opena2a scan           → HackMyAgent  (163 security checks)     │
│  opena2a secrets        → Secretless AI (credential protection)  │
│  opena2a mcp            → MCP server signing and trust           │
│  opena2a benchmark      → OASB (222 attack scenarios)            │
│  opena2a harden-soul    → ABGS (behavioral governance)           │
│  opena2a shield init    → All of the above, one command          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Recent Updates

| Date | Update |
|------|--------|
| Mar 15 | **opena2a-cli v0.7.2** — Shadow AI detection with governance scoring, HTML reports, CSV export, `--registry` enrichment |
| Mar 15 | **HackMyAgent v0.10.1** — 163 checks (up from 147), attack taxonomy, CVE-2026-25253 detection |
| Mar 14 | **Secretless AI v0.12.4** — MCP server credential protection, broker auth hardening |
| Mar 11 | **opena2a-cli v0.5.11** — Runtime command fixes, Shield improvements |
| Mar 10 | **OASB-2** — Agent Soul specification published, 72 behavioral governance controls |
| Mar 5 | **Secretless AI v0.11.4** — HashiCorp Vault backend, graceful fallback |
| Mar 4 | **ABGS v1.0** — Agent Behavioral Governance Specification, 9 domains, 72 controls |

## License

All tools are Apache-2.0.
