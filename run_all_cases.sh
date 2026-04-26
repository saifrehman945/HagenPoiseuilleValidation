#!/usr/bin/env bash

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
openfoam_bashrc="/opt/openfoam12/etc/bashrc"

ensure_openfoam_env() {
    if command -v blockMesh >/dev/null 2>&1 && command -v foamCleanTutorials >/dev/null 2>&1; then
        return 0
    fi

    if [[ -r "$openfoam_bashrc" ]]; then
        # shellcheck disable=SC1090
        source "$openfoam_bashrc"
        return 0
    fi

    echo "OpenFOAM environment is not loaded and $openfoam_bashrc was not found." >&2
    return 1
}

usage() {
    cat <<'EOF'
Usage: ./run_all_cases.sh [case0 case1 ...]

Runs the Hagen-Poiseuille validation cases from a clean state:
  - foamCleanTutorials
  - blockMesh
  - checkMesh
  - solver from system/controlDict

If no case names are provided, all cases are run in order.
EOF
}

get_solver() {
    local control_dict=$1

    awk '
        /^[[:space:]]*application[[:space:]]+/ {
            gsub(/;/, "", $2)
            print $2
            exit
        }
    ' "$control_dict"
}

run_case() {
    local case_dir=$1
    local solver

    pushd "$repo_root/$case_dir" >/dev/null || return 1

    solver="$(get_solver system/controlDict)"
    if [[ -z "$solver" ]]; then
        echo "[$case_dir] Unable to determine solver from system/controlDict" >&2
        popd >/dev/null
        return 1
    fi

    if ! command -v "$solver" >/dev/null 2>&1; then
        echo "[$case_dir] Solver '$solver' is not available in PATH" >&2
        popd >/dev/null
        return 1
    fi

    echo
    echo "===== Running $case_dir with $solver ====="

    if ! foamCleanTutorials; then
        echo "[$case_dir] foamCleanTutorials failed" >&2
        popd >/dev/null
        return 1
    fi

    if ! blockMesh | tee log.blockMesh; then
        echo "[$case_dir] blockMesh failed" >&2
        popd >/dev/null
        return 1
    fi

    if checkMesh | tee log.checkMesh; then
        :
    elif [[ "$case_dir" == "case3" ]]; then
        echo "[$case_dir] checkMesh reported the expected bad mesh; continuing to the solver."
    else
        echo "[$case_dir] checkMesh failed" >&2
        popd >/dev/null
        return 1
    fi

    if ! "$solver" | tee "log.${solver}"; then
        echo "[$case_dir] $solver failed" >&2
        popd >/dev/null
        return 1
    fi

    popd >/dev/null || return 1
    return 0
}

main() {
    local -a all_cases=(case0 case1 case2 case3)
    local -a cases=()
    local -a failures=()
    local case_dir

    ensure_openfoam_env || exit 1

    if [[ $# -eq 0 ]]; then
        cases=("${all_cases[@]}")
    else
        for case_dir in "$@"; do
            if [[ "$case_dir" == "-h" || "$case_dir" == "--help" ]]; then
                usage
                exit 0
            fi

            if [[ ! -d "$repo_root/$case_dir" ]]; then
                echo "Unknown case directory: $case_dir" >&2
                exit 1
            fi

            cases+=("$case_dir")
        done
    fi

    for case_dir in "${cases[@]}"; do
        if ! run_case "$case_dir"; then
            failures+=("$case_dir")
        fi
    done

    echo
    if [[ ${#failures[@]} -eq 0 ]]; then
        echo "All requested cases completed."
        exit 0
    fi

    echo "Cases failed: ${failures[*]}" >&2
    exit 1
}

main "$@"
