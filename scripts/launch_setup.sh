#!/bin/bash
# Launch Claude Code to set up a multi-node cluster
# Usage: ./launch_setup.sh PUBLIC1:PRIVATE1 PUBLIC2:PRIVATE2 ...
# Example: ./launch_setup.sh 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 PUBLIC_IP1:PRIVATE_IP1 [PUBLIC_IP2:PRIVATE_IP2 ...]"
    echo "Example: $0 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17"
    exit 1
fi

# Build the node mapping table
MAPPING="Public IP | Private IP"
MAPPING+="\n----------|----------"

for arg in "$@"; do
    IFS=':' read -r pub priv <<< "$arg"
    MAPPING+="\n$pub | $priv"
done

# Create the prompt
PROMPT="Set up these nodes:

$MAPPING

Run the setup_cluster.sh script with these IPs."

# Launch Claude Code with the prompt
echo "Launching Claude Code with node mapping..."
echo -e "$PROMPT"
echo ""

# Use --dangerously-skip-permissions to allow automated execution
# Or use regular mode for interactive approval
exec claude -p "$PROMPT"
