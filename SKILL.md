---
name: multinode-setup
description: Automates setup of remote GPU rental machines (single or multi-node). Triggered when user provides a mapping of public IPs to private IPs for nodes to set up, or asks to configure remote machines for distributed training.
---

# Multi-Node Remote Machine Setup

This skill automates the setup of rented GPU machines using the `multinode_claude.sh` script.

## Workflow

When user provides a node mapping (public IP → private IP):

1. **Parse the mapping** - Extract public and private IPs for each node
2. **Identify head node** - First node in the list is the head node (NID=0, IHN=true)
3. **Copy and execute script** - SSH using public IPs (user: `ubuntu`), copy script, run with env vars
4. **Verify setup** - Check Docker and Ray status
5. **Update local SSH config** (last, requires approval) - Add/update `~/.ssh/config` entries:
   - `rental0` → head node (first in list)
   - `rental1`, `rental2`, ... → worker nodes

## Script Variables

The setup script requires:
- `RAY_HEAD_IP`: Private IP of the head node (for Ray cluster coordination)
- `NID`: Node ID (0 for head, 1, 2, ... for workers) - used in networking setup
- `IHN`: "Is Head Node" - set to `true` only for node 0

## Execution Steps

### Step 1: Parse Node Mapping

User provides mapping in format:
```
Public IP       Private IP
147.185.40.110  10.15.17.105
147.185.40.111  10.15.17.106
```

### Step 2: Execute Setup (Non-Blocking)

**IMPORTANT: Run all commands in parallel/background. Do NOT wait for completion.**

Use raw public IPs (not rental aliases) since SSH config isn't updated yet.

1. Copy script to all nodes in parallel (use multiple Bash tool calls in ONE message):
```bash
scp /Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh ubuntu@147.185.40.110:/tmp/setup.sh
scp /Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh ubuntu@147.185.40.111:/tmp/setup.sh
```

2. Launch setup on ALL nodes in background (parallel Bash calls, each with `run_in_background: true`):
```bash
ssh ubuntu@147.185.40.110 "nohup bash -c 'NID=0 IHN=true RAY_HEAD_IP=10.15.17.105 bash /tmp/setup.sh' > /workspace/onstart.log 2>&1 &"
ssh ubuntu@147.185.40.111 "nohup bash -c 'NID=1 IHN=false RAY_HEAD_IP=10.15.17.105 bash /tmp/setup.sh' > /workspace/onstart.log 2>&1 &"
```

3. Monitor logs periodically by tailing the log files:
```bash
ssh ubuntu@147.185.40.110 "tail -20 /workspace/onstart.log"
ssh ubuntu@147.185.40.111 "tail -20 /workspace/onstart.log"
```

### Step 3: Verify Setup

After setup completes on all nodes, verify everything is working:

1. **Check Docker container on each node** (run in parallel):
```bash
ssh ubuntu@<PUBLIC_IP> "sudo docker ps | grep sandbox-fusion"
```
Expected: Each node should show a running `sandbox-fusion` container.

2. **Check Ray cluster status** (run on head node only):
```bash
ssh ubuntu@<HEAD_PUBLIC_IP> "ray status"
```
Expected output should show:
- Total number of nodes equals the number of machines
- All nodes have resources (CPU, GPU, memory)
- No dead nodes

### Step 4: Create Final Report

After verification, create a summary report with:

1. **Node Configuration Table**:
   | Node | Public IP | Private IP | NID | Role |
   |------|-----------|------------|-----|------|
   | rental0 | x.x.x.x | y.y.y.y | 0 | Head |
   | rental1 | x.x.x.x | y.y.y.y | 1 | Worker |

2. **Verification Results**:
   - Docker status per node (running/not running)
   - Ray cluster status (number of nodes, total GPUs, any issues)

3. **Quick Access Commands** (will work after Step 5):
   ```bash
   ssh rental0  # Head node
   ssh rental1  # Worker node
   ```

4. **Any Issues/Warnings** encountered during setup

### Step 5: Update SSH Config (Last - Requires Approval)

**Do this step LAST** since editing `~/.ssh/config` requires user approval.

Add entries to `~/.ssh/config` for each node. **If `rentalX` entries already exist, remove them first and replace with the new IPs.** Always override existing entries.

To remove existing rental entries, delete all lines from `Host rentalX` through the next `Host` line (or end of file). Then add fresh entries:

```
Host rental0
    HostName 147.185.40.110
    User ubuntu

Host rental1
    HostName 147.185.40.111
    User ubuntu
```

After this, `ssh rental0`, `ssh rental1`, etc. will work.

## Important Notes

- Run SCP and SSH commands in PARALLEL - do not wait for one to finish before starting others
- Use `nohup` and `&` to run setup in background on remote machines
- Monitor progress by tailing `/workspace/onstart.log` on each node
- The script is idempotent - safe to re-run if setup fails partway
- Worker nodes will wait for head node's Ray to be ready (built into the script)
- ALWAYS verify Docker and Ray status before creating the final report

## Example Session

User: "Set up these nodes:
Public IP: 147.185.40.110, Private IP: 10.15.17.105
Public IP: 147.185.40.111, Private IP: 10.15.17.106"

Claude should:
1. Identify 10.15.17.105 as head node private IP
2. Copy script to BOTH machines in parallel using raw IPs (two scp commands in one message)
3. Launch setup on ALL nodes in background using raw IPs (two ssh commands in one message, each using nohup)
4. Periodically check logs: `ssh ubuntu@<IP> "tail -20 /workspace/onstart.log"` etc.
5. Verify Docker is running on all nodes: `ssh ubuntu@<IP> "sudo docker ps | grep sandbox-fusion"`
6. Verify Ray cluster: `ssh ubuntu@<HEAD_IP> "ray status"`
7. Create final report with node table, verification results, and quick access commands
8. **LAST:** Update `~/.ssh/config` with rental0 (147.185.40.110) and rental1 (147.185.40.111)
