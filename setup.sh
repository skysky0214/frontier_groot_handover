#!/bin/bash
# Clone the 3 forks at the correct branches and lay them out under repos/.
# Run from the root of frontier_groot_handover.
# Requires: ssh key for GitHub (skysky0214 + ROBOTIS-move membership for frontier_simulation).

set -e

REPOS_DIR="$(dirname "$0")/repos"
mkdir -p "$REPOS_DIR"

clone_or_update() {
    local repo_ssh="$1"
    local branch="$2"
    local target="$3"

    if [ -d "$target/.git" ]; then
        echo "[exists] $target — fetching + checking out $branch"
        git -C "$target" fetch origin "$branch"
        git -C "$target" checkout "$branch"
        git -C "$target" pull --ff-only
    else
        echo "[clone] $repo_ssh -> $target (branch: $branch)"
        git clone -b "$branch" "$repo_ssh" "$target"
    fi
}

# 1. Isaac-GR00T fork (GR00T VLA: fine-tune + server + view_dropout/TRT/timing patches)
clone_or_update \
    git@github.com:skysky0214/Isaac-GR00T.git \
    frontier_groot \
    "$REPOS_DIR/Isaac-GR00T"

# 2. robotis_lab fork — renamed to elevator_button_press_task
#    (Isaac Sim environment, Frontier robot, teacher script, inference_demos, modality configs)
clone_or_update \
    git@github.com:skysky0214/elevator_button_press_task.git \
    frontier_groot \
    "$REPOS_DIR/elevator_button_press_task"

# 3. ROBOTIS-move/frontier_simulation (Zenoh inference bridge + 5-floor elevator USD)
#    Requires ROBOTIS-move org access.
clone_or_update \
    git@github.com:ROBOTIS-move/frontier_simulation.git \
    feature-zenoh-inference-groot \
    "$REPOS_DIR/frontier_simulation"

echo
echo "Done. Layout:"
ls -1 "$REPOS_DIR"
echo
echo "Next steps:"
echo "  - Mount the DataCrunch NFS at /mnt/Dataset (see HANDOFF.md §6)."
echo "  - Start the isaac-sim container (docker start isaac-sim)."
echo "  - Run the 4-stage pipeline as described in HANDOFF.md §5."
