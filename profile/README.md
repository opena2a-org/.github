<div align="center">

# OpenA2A

**Open-source security for AI agents**

[Website](https://opena2a.org) · [Discord](https://discord.gg/uRZa3KXgEn) · [Email](mailto:info@opena2a.org)

</div>

---

OpenA2A builds open-source tools for securing AI agents in production. AI agents are the fastest-growing category of non-human identities, and most organizations have no governance, no visibility, and no security controls around them. We're building the infrastructure to fix that — identity management, runtime protection, security scanning, compliance benchmarks, behavioral governance, and credential management for AI developer tools. Everything is Apache-2.0, self-hostable, and designed to work independently or together.

## Recent Updates

| Date | Project | Change |
|------|---------|--------|
| Mar 4 | **HackMyAgent v0.9.4** | OASB v2: 68 behavioral governance controls across 8 domains. Conformance levels (Essential/Standard/Hardened), `--deep` LLM semantic analysis, `secure --benchmark oasb-2` composite scoring. |
| Mar 4 | **AGS v1.0** | Agent Governance Specification published — behavioral safety framework for AI agents, 8 domains, 68 controls, templates and examples for all 4 agent tiers. |
| Mar 4 | **opena2a-cli v0.3.7** | `scan-soul` and `harden-soul` commands added. Native `identity` command. Dead-end CLI outputs fixed. |
| Feb 19 | **OASB** | 40 AI-layer test scenarios added (222 total). Prompt, MCP, A2A scanning via ARP v0.2.0. |
| Feb 19 | **ARP v0.2.0** | AI-layer interceptors, HTTP reverse proxy, 20 threat detection patterns. |
| Feb 19 | **HackMyAgent** | MCP JSON-RPC and A2A attack modes — 7 categories, 70 payloads. |

## Projects

| Project | Description | Install |
|---------|-------------|---------|
| **[opena2a-cli](https://github.com/opena2a-org/opena2a)** | Unified CLI — scan, protect, guard, benchmark, scan-soul, identity. Entry point for all OpenA2A tools. | `npm install -g opena2a-cli` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | Security scanner — 147 checks, OASB-1 benchmark, OASB-2 composite, behavioral governance (scan-soul), attack mode | `npx hackmyagent secure` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Credential management for AI coding tools — Claude Code, Cursor, Windsurf | `npx secretless-ai init` |
| **[AGS](https://github.com/opena2a-org/agent-governance-spec)** | Agent Governance Specification — 8 domains, 68 controls, templates for BASIC/TOOL-USING/AGENTIC/MULTI-AGENT tiers | `npx hackmyagent scan-soul` |
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Identity & access management for AI agents — Ed25519 keypairs, capability policies, audit logging | `pip install aim-sdk` |
| **[OASB](https://github.com/opena2a-org/open-agent-security-benchmark)** | Open Agent Security Benchmark — OASB-1 (46 infra controls) + OASB-2 (68 governance controls), 222 test scenarios | `npm install @opena2a/oasb` |
| **[ARP](https://github.com/opena2a-org/agent-runtime-protection)** | Agent Runtime Protection — process, network, filesystem monitoring | `npm install @opena2a/arp` |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training | `docker pull opena2a/dvaa` |

## How They Fit Together

```
┌─────────────────────────────────────────────────────────────────┐
│              opena2a-cli  (unified entry point)                 │
│              npm install -g opena2a-cli                         │
├─────────────────────────────────────────────────────────────────┤
│                        Your AI Agent                            │
│                                                                 │
│  Secretless AI  → Credential management for dev tools           │
│  AIM            → Identity, governance, access control          │
│  AGS / scan-soul→ Behavioral governance (SOUL.md, 68 ctrls)     │
│  ARP            → Runtime process/network/file monitoring       │
│  HackMyAgent    → Scan, harden, attack-test, OASB-1+2           │
│  OASB           → Compliance benchmark (46+68 controls)         │
│  DVAA           → Train your team on AI agent security          │
└─────────────────────────────────────────────────────────────────┘
```

## Upstream Contributions

We contribute security fixes back to the open-source projects we depend on and audit.

**[OpenClaw](https://github.com/openclaw/openclaw)** — 8 security PRs (7 merged, 1 open):
- Credential redaction in gateway config responses ([#9858](https://github.com/openclaw/openclaw/pull/9858))
- Skill/plugin code safety scanner ([#9806](https://github.com/openclaw/openclaw/pull/9806))
- Path traversal prevention in A2UI file serving ([#10525](https://github.com/openclaw/openclaw/pull/10525))
- Security headers for gateway HTTP responses ([#10526](https://github.com/openclaw/openclaw/pull/10526))
- Timing-safe comparison for hook token auth ([#10527](https://github.com/openclaw/openclaw/pull/10527))
- Supply chain hardening with --ignore-scripts ([#10528](https://github.com/openclaw/openclaw/pull/10528))
- File permission enforcement for credential files ([#10529](https://github.com/openclaw/openclaw/pull/10529))
- Skill scanner false positive reduction ([#10530](https://github.com/openclaw/openclaw/pull/10530))

**[Nanobot](https://github.com/HKUDS/nanobot)** — 1 security PR (open):
- Path traversal, XSS, and shell escape fixes ([#472](https://github.com/HKUDS/nanobot/pull/472))

## License

All projects are Apache-2.0.
