<div align="center">

# OpenA2A

**Open-source security for AI agents**

[Website](https://opena2a.org) · [Discord](https://discord.gg/uRZa3KXgEn) · [Email](mailto:info@opena2a.org)

</div>

---

## Projects

| Project | Description | Install |
|---------|-------------|---------|
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Identity & access management for AI agents | `docker pull ghcr.io/opena2a-org/aim-server` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | Security scanner — 147 checks, attack mode, auto-fix | `npx hackmyagent secure` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Keep credentials out of AI context windows | `npx secretless-ai init` |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training | `npx dvaa` |
| **[OASB](https://oasb.ai)** | Open Agent Security Benchmark | `npx hackmyagent benchmark` |

## How They Fit Together

```
┌─────────────────────────────────────────────────────┐
│                   Your AI Agent                      │
│                                                      │
│  Secretless AI     → Credentials never reach the LLM │
│  AIM               → Identity, governance, access     │
│  HackMyAgent       → Scan, harden, attack-test       │
│  OASB              → Compliance benchmark             │
│  DVAA              → Train your team on AI security   │
└─────────────────────────────────────────────────────┘
```

## License

All projects are Apache-2.0.
