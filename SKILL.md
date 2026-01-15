---
name: multinode-setup
description: Automates setup of remote GPU rental machines (single or multi-node). Triggered when user provides a mapping of public IPs to private IPs for nodes to set up, or asks to configure remote machines for distributed training.
---

# Multi-Node Remote Machine Setup

This skill automates the setup of rented GPU machines using a single setup script.

## Quick Start

When user provides a node mapping, run:

```bash
~/.claude/skills/multinode-setup/scripts/setup_cluster.sh PUBLIC1:PRIVATE1 PUBLIC2:PRIVATE2 ...
```

Example:
```bash
~/.claude/skills/multinode-setup/scripts/setup_cluster.sh 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17
```

The first node is always the head node (rental0).

## What the Script Does

1. **Updates `~/.ssh/config`** - Creates rental0, rental1, ... aliases (overwrites existing)
2. **Copies setup script** - SCPs `multinode_claude.sh` to all nodes in parallel
3. **Runs setup on all nodes** - Executes with correct `NID`, `IHN`, and `RAY_HEAD_IP` vars
4. **Verifies setup** - Checks Docker and Ray cluster status
5. **Prints final report** - Node table and quick access commands

## Input Format

User provides mapping in various formats. Parse into `PUBLIC:PRIVATE` pairs:

```
Public IP       Private IP
147.185.40.110  10.15.17.105
147.185.40.111  10.15.17.106
```

Becomes:
```bash
./setup_cluster.sh 147.185.40.110:10.15.17.105 147.185.40.111:10.15.17.106
```

## Script Variables

The underlying `multinode_claude.sh` uses:
- `RAY_HEAD_IP`: Private IP of the head node (auto-set to first node's private IP)
- `NID`: Node ID (0 for head, 1, 2, ... for workers)
- `IHN`: "Is Head Node" - `true` only for node 0

## After Setup

Quick access commands:
```bash
ssh rental0  # Head node
ssh rental1  # Worker node
ssh rental0 "ray status"  # Check Ray cluster
```

## Troubleshooting

If setup fails, check logs:
```bash
cat /tmp/setup_rental0.log  # Local log for head node
cat /tmp/setup_rental1.log  # Local log for worker node
ssh rental0 "cat /workspace/onstart.log"  # Remote log
```

The setup script is idempotent - safe to re-run.
