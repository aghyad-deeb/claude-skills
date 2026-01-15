#!/bin/bash
# Multi-Node Cluster Setup Script
# Usage: ./setup_cluster.sh PUBLIC_IP1:PRIVATE_IP1 PUBLIC_IP2:PRIVATE_IP2 ...
# First node is the head node (rental0), rest are workers (rental1, rental2, ...)

set -euo pipefail

SETUP_SCRIPT="/Users/aghyaddeeb/Documents/coding/onstart/multinode_claude.sh"
SSH_CONFIG="$HOME/.ssh/config"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "[$(date '+%H:%M:%S')] $*"; }
log_success() { echo -e "[$(date '+%H:%M:%S')] ${GREEN}✓${NC} $*"; }
log_error() { echo -e "[$(date '+%H:%M:%S')] ${RED}✗${NC} $*" >&2; }
log_warn() { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}!${NC} $*"; }

# Arrays to store node info
declare -a PUBLIC_IPS
declare -a PRIVATE_IPS

# Parse arguments
parse_args() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 PUBLIC_IP1:PRIVATE_IP1 [PUBLIC_IP2:PRIVATE_IP2 ...]"
        echo "Example: $0 147.185.41.18:10.15.22.9 147.185.41.19:10.15.22.17"
        exit 1
    fi

    for arg in "$@"; do
        IFS=':' read -r pub priv <<< "$arg"
        if [ -z "$pub" ] || [ -z "$priv" ]; then
            log_error "Invalid format: $arg (expected PUBLIC:PRIVATE)"
            exit 1
        fi
        PUBLIC_IPS+=("$pub")
        PRIVATE_IPS+=("$priv")
    done

    log "Parsed ${#PUBLIC_IPS[@]} node(s)"
    log "Head node: ${PUBLIC_IPS[0]} (private: ${PRIVATE_IPS[0]})"
}

# Update SSH config with rental aliases
update_ssh_config() {
    log "Updating SSH config..."

    # Backup existing config
    if [ -f "$SSH_CONFIG" ]; then
        cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
    fi

    # Remove existing rental entries
    if [ -f "$SSH_CONFIG" ]; then
        # Create temp file without rental entries
        awk '
            /^Host rental[0-9]+/ { skip=1; next }
            /^Host / { skip=0 }
            !skip { print }
        ' "$SSH_CONFIG" > "$SSH_CONFIG.tmp"
        mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
    fi

    # Add new rental entries
    for i in "${!PUBLIC_IPS[@]}"; do
        cat >> "$SSH_CONFIG" << EOF

Host rental$i
    HostName ${PUBLIC_IPS[$i]}
    User ubuntu
EOF
    done

    log_success "SSH config updated with ${#PUBLIC_IPS[@]} rental entries"
}

# Copy setup script to all nodes in parallel
copy_scripts() {
    log "Copying setup script to all nodes..."

    local pids=()
    for i in "${!PUBLIC_IPS[@]}"; do
        scp $SSH_OPTS "$SETUP_SCRIPT" "ubuntu@${PUBLIC_IPS[$i]}:/tmp/setup.sh" &
        pids+=($!)
    done

    # Wait for all copies to complete
    local failed=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            log_error "Failed to copy to rental$i (${PUBLIC_IPS[$i]})"
            ((failed++))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "Script copied to all ${#PUBLIC_IPS[@]} nodes"
    else
        log_error "Failed to copy to $failed node(s)"
        exit 1
    fi
}

# Run setup on all nodes
run_setup() {
    local head_private="${PRIVATE_IPS[0]}"

    log "Starting setup on all nodes (RAY_HEAD_IP=$head_private)..."

    # Start all nodes in parallel - workers will wait for head's Ray port
    local pids=()
    local logfiles=()

    for i in "${!PUBLIC_IPS[@]}"; do
        local nid=$i
        local ihn="false"
        [ $i -eq 0 ] && ihn="true"

        local logfile="/tmp/setup_rental${i}.log"
        logfiles+=("$logfile")

        log "Starting rental$i (NID=$nid, IHN=$ihn)..."
        ssh $SSH_OPTS "ubuntu@${PUBLIC_IPS[$i]}" \
            "NID=$nid IHN=$ihn RAY_HEAD_IP=$head_private bash /tmp/setup.sh" \
            > "$logfile" 2>&1 &
        pids+=($!)
    done

    # Monitor progress
    log "Setup running on ${#pids[@]} nodes. Monitoring..."

    local completed=0
    local failed=0
    declare -a done_nodes

    while [ $((completed + failed)) -lt ${#pids[@]} ]; do
        for i in "${!pids[@]}"; do
            # Skip already processed
            [[ " ${done_nodes[*]} " =~ " $i " ]] && continue

            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                # Process finished
                if wait "${pids[$i]}"; then
                    log_success "rental$i completed"
                    ((completed++))
                else
                    log_error "rental$i failed (check ${logfiles[$i]})"
                    ((failed++))
                fi
                done_nodes+=($i)
            fi
        done
        sleep 5
    done

    if [ $failed -gt 0 ]; then
        log_warn "$failed node(s) failed setup"
        return 1
    fi

    log_success "All ${#pids[@]} nodes completed setup"
}

# Verify Docker is running on all nodes
verify_docker() {
    log "Verifying Docker on all nodes..."

    local failed=0
    for i in "${!PUBLIC_IPS[@]}"; do
        if ssh $SSH_OPTS "ubuntu@${PUBLIC_IPS[$i]}" "sudo docker ps | grep -q sandbox-fusion" 2>/dev/null; then
            log_success "rental$i: Docker sandbox-fusion running"
        else
            log_error "rental$i: Docker sandbox-fusion NOT running"
            ((failed++))
        fi
    done

    return $failed
}

# Verify Ray cluster status
verify_ray() {
    log "Verifying Ray cluster on head node..."

    local ray_status
    ray_status=$(ssh $SSH_OPTS "ubuntu@${PUBLIC_IPS[0]}" "ray status 2>/dev/null" || true)

    if [ -z "$ray_status" ]; then
        log_error "Could not get Ray status"
        return 1
    fi

    echo "$ray_status"

    # Check node count
    local node_count
    node_count=$(echo "$ray_status" | grep -oP '\d+ node' | grep -oP '\d+' | head -1 || echo "0")

    if [ "$node_count" -eq "${#PUBLIC_IPS[@]}" ]; then
        log_success "Ray cluster has all $node_count nodes"
    else
        log_warn "Ray cluster has $node_count nodes (expected ${#PUBLIC_IPS[@]})"
    fi
}

# Print final report
print_report() {
    echo ""
    echo "=============================================="
    echo "           CLUSTER SETUP COMPLETE"
    echo "=============================================="
    echo ""
    echo "Node Configuration:"
    echo "-------------------"
    printf "%-10s %-18s %-15s %-5s %-8s\n" "Node" "Public IP" "Private IP" "NID" "Role"
    printf "%-10s %-18s %-15s %-5s %-8s\n" "----" "---------" "----------" "---" "----"

    for i in "${!PUBLIC_IPS[@]}"; do
        local role="Worker"
        [ $i -eq 0 ] && role="Head"
        printf "%-10s %-18s %-15s %-5s %-8s\n" "rental$i" "${PUBLIC_IPS[$i]}" "${PRIVATE_IPS[$i]}" "$i" "$role"
    done

    echo ""
    echo "Quick Access:"
    echo "-------------"
    for i in "${!PUBLIC_IPS[@]}"; do
        local role="worker"
        [ $i -eq 0 ] && role="head"
        echo "  ssh rental$i  # $role node"
    done

    echo ""
    echo "Useful Commands:"
    echo "----------------"
    echo "  ssh rental0 'ray status'              # Check Ray cluster"
    echo "  ssh rental0 'sudo docker ps'          # Check Docker"
    echo "  ssh rental0 'tail -50 /workspace/onstart.log'  # View setup log"
    echo ""
}

# Main
main() {
    parse_args "$@"

    echo ""
    log "Starting multi-node cluster setup..."
    echo ""

    update_ssh_config
    copy_scripts
    run_setup

    echo ""
    log "Running verifications..."
    verify_docker || true
    echo ""
    verify_ray || true

    print_report
}

main "$@"
