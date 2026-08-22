# LangGraph Runtime (Planned)

A LangGraph-based runtime for teams already using the LangChain ecosystem.

## Status

Not yet implemented. Contributions welcome.

## Design

- Use LangGraph's `StateGraph` to model skill execution as graph nodes
- MCP tools exposed via LangChain tool adapters
- Skills parsed from SKILL.md into LangGraph node definitions
- Memory backed by the same PVC as other runtimes

## Getting Started

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for how to add a new runtime.
