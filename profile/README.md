<div align="center">

# OpenA2A

**Open-source security for AI agents**

[Website](https://opena2a.org) · [Discord](https://discord.gg/uRZa3KXgEn) · [Email](mailto:info@opena2a.org)

</div>

---

OpenA2A builds open-source tools for securing AI agents in production. AI agents are the fastest-growing category of non-human identities, and most organizations have no governance, no visibility, and no security controls around them. We're building the infrastructure to fix that -- identity management, runtime protection, security scanning, compliance benchmarks, and credential management for AI developer tools. Everything is Apache-2.0, self-hostable, and designed to work independently or together.

## Recent Updates

| Date | Project | Change |
|------|---------|--------|
| Feb 19 | **OASB** | 40 AI-layer test scenarios added (222 total). Prompt, MCP, A2A scanning via ARP v0.2.0. |
| Feb 19 | **ARP v0.2.0** | AI-layer interceptors, HTTP reverse proxy, 20 threat detection patterns. |
| Feb 19 | **HackMyAgent** | MCP JSON-RPC and A2A attack modes -- 7 categories, 70 payloads. |
| Feb 18 | **DVAA v0.4.0** | MCP JSON-RPC and A2A message endpoints. 10 agents across 3 protocols. |

## Projects

| Project | Description | Install |
|---------|-------------|---------|
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Identity & access management for AI agents | `pip install aim-sdk` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | Security scanner -- 147 checks, attack mode, auto-fix | `npx hackmyagent secure` |
| **[OASB](https://github.com/opena2a-org/oasb)** | Open Agent Security Benchmark -- 182 attack scenarios | `npm install @opena2a/oasb` |
| **[ARP](https://github.com/opena2a-org/arp)** | Agent Runtime Protection -- process, network, filesystem monitoring | `npm install @opena2a/arp` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Credential management for AI coding tools -- Claude Code, Cursor, Windsurf | `npx secretless-ai init` |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training | `docker pull opena2a/dvaa` |

## How They Fit Together

```
┌──────────────────────────────────────────────────────────┐
│                      Your AI Agent                        │
│                                                           │
│  Secretless AI  → Credential management for dev tools     │
│  AIM            → Identity, governance, access control    │
│  ARP            → Runtime process/network/file monitoring │
│  HackMyAgent    → Scan, harden, attack-test               │
│  OASB           → Compliance benchmark (46 controls)      │
│  DVAA           → Train your team on AI agent security    │
└──────────────────────────────────────────────────────────┘
```

## Upstream Contributions

We contribute security fixes back to the open-source projects we depend on and audit.

**[OpenClaw](https://github.com/openclaw/openclaw)** -- 8 security PRs (2 merged, 6 open):
- Credential redaction in gateway config responses ([#9858](https://github.com/openclaw/openclaw/pull/9858))
- Skill/plugin code safety scanner ([#9806](https://github.com/openclaw/openclaw/pull/9806))
- Path traversal prevention in A2UI file serving ([#10525](https://github.com/openclaw/openclaw/pull/10525))
- Security headers for gateway HTTP responses ([#10526](https://github.com/openclaw/openclaw/pull/10526))
- Timing-safe comparison for hook token auth ([#10527](https://github.com/openclaw/openclaw/pull/10527))
- Supply chain hardening with --ignore-scripts ([#10528](https://github.com/openclaw/openclaw/pull/10528))
- File permission enforcement for credential files ([#10529](https://github.com/openclaw/openclaw/pull/10529))
- Skill scanner false positive reduction ([#10530](https://github.com/openclaw/openclaw/pull/10530))

**[Nanobot](https://github.com/HKUDS/nanobot)** -- 1 security PR (open):
- Path traversal, XSS, and shell escape fixes ([#472](https://github.com/HKUDS/nanobot/pull/472))

## License

All projects are Apache-2.0.
