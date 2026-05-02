---
type: "query"
date: "2026-05-02T01:28:20.421833+00:00"
question: "Why does GameEventBus signal contract specification bridge agent workflow, combat VFX, and graphify?"
contributor: "graphify"
source_nodes: ["feature_spec_game_event_bus_doc", "combat_vfx_bus_subscription", "agents_autoload_gameeventbus"]
---

# Q: Why does GameEventBus signal contract specification bridge agent workflow, combat VFX, and graphify?

## Answer

The hub links three lanes: (1) Agent/graphify: Phase16 decision + decisions_log + CLAUDE session rules chain to CLAUDE.md and GRAPH_REPORT; (2) Combat VFX: depends_on_contract edge to VFXManager bus subscriptions in combat_vfx spec then INFERRED to VFXManager autoload; (3) Implementation picture: implements link to AGENTS.md GameEventBus line plus aligned_with agent_brief bus-only rule.

## Source Nodes

- feature_spec_game_event_bus_doc
- combat_vfx_bus_subscription
- agents_autoload_gameeventbus