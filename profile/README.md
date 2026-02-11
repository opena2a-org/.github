<div align="center">

# OpenA2A

**Open-source security for AI agents**

[Website](https://opena2a.org) · [Discord](https://discord.gg/uRZa3KXgEn) · [Email](mailto:info@opena2a.org)

</div>

---

## Projects

| Project | Description | Install |
|---------|-------------|---------|
| **[AIM](https://github.com/opena2a-org/agent-identity-management)** | Identity & access management for AI agents | `pip install aim-sdk` |
| **[HackMyAgent](https://github.com/opena2a-org/hackmyagent)** | Security scanner -- 147 checks, attack mode, auto-fix | `npx hackmyagent secure` |
| **[OASB](https://github.com/opena2a-org/oasb)** | Open Agent Security Benchmark -- 182 attack scenarios | `npm install @opena2a/oasb` |
| **[ARP](https://github.com/opena2a-org/arp)** | Agent Runtime Protection -- process, network, filesystem monitoring | `npm install @opena2a/arp` |
| **[Secretless AI](https://github.com/opena2a-org/secretless-ai)** | Keep credentials out of AI context windows | `npx secretless-ai init` |
| **[DVAA](https://github.com/opena2a-org/damn-vulnerable-ai-agent)** | Deliberately vulnerable AI agents for security training | `docker pull opena2a/dvaa` |

## How They Fit Together

```
┌──────────────────────────────────────────────────────────┐
│                      Your AI Agent                        │
│                                                           │
│  Secretless AI  → Credentials never reach the LLM        │
│  AIM            → Identity, governance, access control    │
│  ARP            → Runtime process/network/file monitoring │
│  HackMyAgent    → Scan, harden, attack-test               │
│  OASB           → Compliance benchmark (46 controls)      │
│  DVAA           → Train your team on AI agent security    │
└──────────────────────────────────────────────────────────┘
```

## License

All projects are Apache-2.0.
