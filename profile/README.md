> **[OpenA2A](https://github.com/opena2a-org/opena2a)**: [HackMyAgent](https://github.com/opena2a-org/hackmyagent) · [Secretless AI](https://github.com/opena2a-org/secretless-ai) · [AIM](https://github.com/opena2a-org/agent-identity-management) · [Browser Guard](https://github.com/opena2a-org/AI-BrowserGuard) · [DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent) · [OASB](https://oasb.ai)

<div align="center">

# OpenA2A

**Open-source security for AI agents**

[Website](https://opena2a.org) · [OASB Benchmark](https://oasb.ai) · [Discord](https://discord.gg/uRZa3KXgEn) · [Email](mailto:info@opena2a.org)

</div>

---

OpenA2A builds open-source tools for securing AI agents in production. AI agents are the fastest-growing category of non-human identities, and most organizations have no governance, no visibility, and no security controls around them. We're building the infrastructure to fix that -- identity management, runtime protection, security scanning, compliance benchmarks, behavioral governance, and credential management for AI developer tools. Everything is Apache-2.0, self-hostable, and designed to work independently or together.

## Recent Updates

| Date | Project | Change |
|------|---------|--------|
| Mar 10 | **OASB-2** | [Agent Soul specification](https://oasb.ai/oasb-2) published -- 72 behavioral governance controls across 9 domains, 4 agent tiers, 4 conformance levels. |
| Mar 5 | **opena2a-cli v0.5.3** | Workspace binary resolution, graceful backend fallback, vault migration fix. |
| Mar 5 | **Secretless AI v0.11.4** | HashiCorp Vault backend, graceful fallback when 1Password/Vault unavailable, `strict` mode for migrations. |
| Mar 4 | **HackMyAgent v0.9.8** | OASB-2 composite scoring, `--deep` LLM semantic analysis, `scan-soul`/`harden-soul` commands, CLI prefix detection. |
| Mar 4 | **ABGS v1.0** | Agent Behavioral Governance Specification -- behavioral safety framework, 9 domains, 72 controls, templates for all 4 agent tiers. |
| Feb 19 | **OASB** | 40 AI-layer test scenarios added (222 total). Prompt, MCP, A2A scanning via ARP v0.2.0. |

## Projects

| Project | Description | Install |
|---------|-------------|---------|
| **[opena2a-cli](https://github.com/opena2a-org/opena2a)** | Unified CLI -- scan, protect, guard, benchmark, review, shield. Entry point for all OpenA2A tools. | `npm install -g opena2a-cli` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | Security scanner -- 150+ checks, OASB benchmarks, attack simulation, runtime protection, behavioral governance | `npx hackmyagent secure` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Credential management for AI coding tools -- Claude Code, Cursor, Windsurf. 4 backends (local, keychain, 1Password, Vault). | `npx secretless-ai init` |
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Identity & access management for AI agents -- Ed25519 keypairs, capability policies, audit logging | Self-hosted (Go) |
| **[AI Browser Guard](https://github.com/opena2a-org/AI-BrowserGuard)** | Browser extension for AI agent detection and control -- 4-layer detection, delegation engine | Chrome Web Store |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training -- 10 agents across 3 protocols | `docker pull opena2a/dvaa` |
| **Trust Registry** | Supply chain verification and trust scores | Coming soon |

### Specifications

| Spec | Description | Website |
|------|-------------|---------|
| **[OASB-1](https://oasb.ai/oasb-1)** | Open Agent Security Benchmark -- 46 infrastructure security controls, L1/L2/L3 maturity levels | [oasb.ai/oasb-1](https://oasb.ai/oasb-1) |
| **[OASB-2](https://oasb.ai/oasb-2)** | Agent Soul -- 72 behavioral governance controls, 9 domains, 4 agent tiers, 4 conformance levels | [oasb.ai/oasb-2](https://oasb.ai/oasb-2) |
| **[OASB Eval](https://oasb.ai/eval)** | Security product evaluation -- 182 attack scenarios across 10 MITRE ATLAS techniques | [oasb.ai/eval](https://oasb.ai/eval) |

### Included in HackMyAgent

| Component | Description | CLI Command |
|-----------|-------------|-------------|
| **ARP** | Agent Runtime Protection -- process, network, filesystem monitoring | `opena2a runtime` |
| **[ABGS](https://github.com/opena2a-org/oasb)** | Agent Behavioral Governance Specification -- behavioral governance, SOUL.md, 72 controls | `opena2a scan-soul` |
| **[OASB](https://oasb.ai)** | Open Agent Security Benchmark -- OASB-1 + OASB-2, 222 test scenarios | `opena2a benchmark oasb-2` |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training | `opena2a train` |

## How They Fit Together

```
┌─────────────────────────────────────────────────────────────────┐
│              opena2a-cli  (unified entry point)                  │
│              npm install -g opena2a-cli                           │
├─────────────────────────────────────────────────────────────────┤
│                        Your AI Agent                              │
│                                                                   │
│  Secretless AI   -> Credential management for dev tools           │
│  AIM             -> Identity, governance, access control          │
│  HackMyAgent     -> Scan, harden, attack-test                     │
│    |-- ARP       -> Runtime process/network/file monitoring       │
│    |-- ABGS      -> Behavioral governance (SOUL.md, 72 ctrls)    │
│    |-- OASB      -> Compliance benchmark (222 test scenarios)     │
│    +-- DVAA      -> Train your team on AI agent security          │
│  Browser Guard   -> AI agent detection in browser sessions        │
│  Trust Registry  -> Supply chain verification (coming soon)       │
└─────────────────────────────────────────────────────────────────┘
```

## Upstream Contributions

We contribute security fixes back to the open-source projects we depend on and audit.

**[OpenClaw](https://github.com/openclaw/openclaw)** -- 8 security PRs (7 merged, 1 open):
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
