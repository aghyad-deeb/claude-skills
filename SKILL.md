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
3. **Update local SSH config** - Add/update entries in `~/.ssh/config` for easy access:
   - `rental0` → head node (first in list)
   - `rental1`, `rental2`, ... → worker nodes
4. **Prepare the script** - The script at `/Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh` needs `RAY_HEAD_IP` set to the head node's private IP
5. **SSH and execute** - For each node in parallel:
   - SSH using public IP (user: `ubuntu`)
   - Copy the script to `/tmp/setup.sh`
   - Set appropriate environment variables and run

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

### Step 2: Update SSH Config

Add entries to `~/.ssh/config` for each node. First, remove any existing rental entries, then add new ones:

```
Host rental0
    HostName 147.185.40.110
    User ubuntu

Host rental1
    HostName 147.185.40.111
    User ubuntu
```

This allows easy SSH access via `ssh rental0`, `ssh rental1`, etc.

### Step 3: Prepare Commands

For head node (first in list):
```bash
ssh rental0 "NID=0 IHN=true RAY_HEAD_IP=<HEAD_PRIVATE_IP> bash /tmp/setup.sh"
```

For worker nodes:
```bash
ssh rental<N> "NID=<N> IHN=false RAY_HEAD_IP=<HEAD_PRIVATE_IP> bash /tmp/setup.sh"
```

### Step 4: Execute (Non-Blocking)

**IMPORTANT: Run all commands in parallel/background. Do NOT wait for completion.**

1. Copy script to all nodes in parallel (use multiple Bash tool calls in ONE message):
```bash
scp /Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh rental0:/tmp/setup.sh
scp /Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh rental1:/tmp/setup.sh
```

2. Launch setup on ALL nodes in background (parallel Bash calls, each with `run_in_background: true`):
```bash
ssh rental0 "nohup bash -c 'NID=0 IHN=true RAY_HEAD_IP=<HEAD_PRIVATE_IP> bash /tmp/setup.sh' > /workspace/onstart.log 2>&1 &"
ssh rental1 "nohup bash -c 'NID=1 IHN=false RAY_HEAD_IP=<HEAD_PRIVATE_IP> bash /tmp/setup.sh' > /workspace/onstart.log 2>&1 &"
```

3. Monitor logs periodically by tailing the log files:
```bash
ssh rental0 "tail -20 /workspace/onstart.log"
ssh rental1 "tail -20 /workspace/onstart.log"
```

### Step 5: Verify Setup

After setup completes on all nodes, verify everything is working:

1. **Check Docker container on each node** (run in parallel):
```bash
ssh rental0 "sudo docker ps | grep sandbox-fusion"
ssh rental1 "sudo docker ps | grep sandbox-fusion"
```
Expected: Each node should show a running `sandbox-fusion` container.

2. **Check Ray cluster status** (run on head node only):
```bash
ssh rental0 "ray status"
```
Expected output should show:
- Total number of nodes equals the number of machines
- All nodes have resources (CPU, GPU, memory)
- No dead nodes

### Step 6: Create Final Report

After verification, create a summary report with:

1. **Node Configuration Table**:
   | Node | Public IP | Private IP | NID | Role |
   |------|-----------|------------|-----|------|
   | rental0 | x.x.x.x | y.y.y.y | 0 | Head |
   | rental1 | x.x.x.x | y.y.y.y | 1 | Worker |

2. **Verification Results**:
   - Docker status per node (running/not running)
   - Ray cluster status (number of nodes, total GPUs, any issues)

3. **Quick Access Commands**:
   ```bash
   ssh rental0  # Head node
   ssh rental1  # Worker node
   ```

4. **Any Issues/Warnings** encountered during setup

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
1. Update `~/.ssh/config` with rental0 (147.185.40.110) and rental1 (147.185.40.111)
2. Identify 10.15.17.105 as head node private IP
3. Copy script to BOTH machines in parallel (two scp commands in one message)
4. Launch setup on ALL nodes in background (two ssh commands in one message, each using nohup)
5. Periodically check logs: `ssh rental0 "tail -20 /workspace/onstart.log"` etc.
6. Verify Docker is running on all nodes: `ssh rentalX "sudo docker ps | grep sandbox-fusion"`
7. Verify Ray cluster: `ssh rental0 "ray status"`
8. Create final report with node table, verification results, and quick access commands
