[private]
default:
    @just --list --unsorted

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')

build_matrix := "build.yaml"

# parse build.yaml and filter targets by expression
_parse_targets $expr: _check_yq_version
    #!/usr/bin/env bash
    attrs="[.board, .shield, .snippet, .\"artifact-name\", .\"cmake-args\"]"
    filter="(($attrs | map(. // [.]) | combinations), ((.include // {})[] | $attrs)) | join(\",\")"
    echo "$(yq -r "$filter" {{build_matrix}} | grep -v "^," | grep -i "${expr/#all/.*}")"

# build firmware for single board & shield combination
_build_single $board $shield $snippet $artifact cmake_args *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board//\//_}}"
    build_dir="{{ build / '$artifact' }}"

    echo "Building firmware for $artifact..."
    west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
        -DZMK_CONFIG="{{ config }}" ${shield:+-DSHIELD="$shield"} {{ cmake_args }}

    if [[ -f "$build_dir/zephyr/zmk.uf2" ]]; then
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.uf2" "{{ out }}/$artifact.uf2"
    else
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.bin" "{{ out }}/$artifact.bin"
    fi

# flash firmware for single board & shield combination
# only needed for boards which do not support UF2
_flash_single $board $shield $artifact:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board//\//_}}"
    build_dir="{{ build / '$artifact' }}"

    echo "Flashing firmware for $artifact..."
    west flash -d "$build_dir"

# List build targets. The sed chain removes version and build variants,
# and prints the shield (if given) or otherwise the board name.
[group('build & draw')]
[doc('list build targets')]
list:
    @just build_matrix={{build_matrix}} _parse_targets all \
        | sed 's|[@/][^,]*,|,|' \
        | sed 's|\([^,]*\),\([^,]\+\),.*|\2|' \
        | sed 's|\([^,]*\),,.*|\1|' \
        | sort \
        | column

# build firmware for targets matching <expr>
[group('build & draw')]
build expr *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just build_matrix={{build_matrix}} _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet artifact cmake_args; do
        just _build_single "$board" "$shield" "$snippet" "$artifact" "$cmake_args" {{ west_args }}
    done

# flash firmware for targets matching <expr>
[group('build & draw')]
flash expr: (build expr)
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just build_matrix={{build_matrix}} _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet artifact cmake_args; do
        just _flash_single "$board" "$shield" "$artifact"
    done

# parse & plot keymap
[group('build & draw')]
draw: _check_yq_version
    #!/usr/bin/env bash
    set -euo pipefail
    # Parse keymap
    keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/base.keymap" \
        --virtual-layers Combos >"{{ draw }}/base.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/base.yaml"
    # Rename conditional layers to show how they are reached (FUN + NUM, NAV + SYM)
    yq -Yi '.layers = (.layers | to_entries | map(if .key == "Sys" then .key = "Sys (FUN + NUM)" elif .key == "Media" then .key = "Media (NAV + SYM)" else . end) | from_entries)' "{{ draw }}/base.yaml"
    # Reorder layers: Num/Sym/Combos after Base, Nav/Fun, then alternates, then extras
    yq -Yi '.layers = {Base: .layers.Base, Num: .layers.Num, Sym: .layers.Sym, Combos: .layers.Combos, Nav: .layers.Nav, Fun: .layers.Fun, Qwerty: .layers.Qwerty, Game: .layers.Game, Gnum: .layers.Gnum, Mouse: .layers.Mouse, Numpad: .layers.Numpad, Intl: .layers.Intl, "Sys (FUN + NUM)": .layers."Sys (FUN + NUM)", "Media (NAV + SYM)": .layers."Media (NAV + SYM)"}' "{{ draw }}/base.yaml"
    # Mark held key for Numpad layer
    yq -Yi '.layers.Numpad[18] = {type: "held"}' "{{ draw }}/base.yaml"
    # Mark held key for Gnum layer
    yq -Yi '.layers.Gnum[38] = {type: "held"}' "{{ draw }}/base.yaml"
    # Mark held keys on layers (keymap-drawer doesn't auto-detect custom behaviors)
    yq -Yi '.layers.Nav[37] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers.Mouse[38] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers.Num[40] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers.Fun[41] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers."Sys (FUN + NUM)"[40] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers."Sys (FUN + NUM)"[41] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers.Intl[36] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers."Media (NAV + SYM)"[18] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers."Media (NAV + SYM)"[37] = {type: "held"}' "{{ draw }}/base.yaml"
    yq -Yi '.layers."Media (NAV + SYM)"[39] = {type: "held"}' "{{ draw }}/base.yaml"
    # Set 2-column layout
    yq -Yi '.draw_config.n_columns = 2' "{{ draw }}/base.yaml"
    # Draw with physical layout from Toucan shield DTS
    keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/base.yaml" \
        -d "zmk-keyboard-toucan/boards/shields/toucan/toucan.dtsi" >"{{ draw }}/base.svg"

# generate minimal cheatsheet (Base, Num, Sym + Combos) in 2x2 grid
[group('build & draw')]
cheatsheet: _check_yq_version
    #!/usr/bin/env bash
    set -euo pipefail
    keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/base.keymap" \
        --virtual-layers Combos >"{{ draw }}/cheatsheet.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/cheatsheet.yaml"
    # Keep only Base, Num, Sym, Combos layers
    yq -Yi '.layers = {Base: .layers.Base, Num: .layers.Num, Sym: .layers.Sym, Combos: .layers.Combos}' "{{ draw }}/cheatsheet.yaml"
    # Mark held keys
    yq -Yi '.layers.Num[40] = {type: "held"}' "{{ draw }}/cheatsheet.yaml"
    yq -Yi '.layers.Sym[39] = {type: "held"}' "{{ draw }}/cheatsheet.yaml"
    # Set 2-column layout
    yq -Yi '.draw_config.n_columns = 2' "{{ draw }}/cheatsheet.yaml"
    keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/cheatsheet.yaml" \
        -d "zmk-keyboard-toucan/boards/shields/toucan/toucan.dtsi" >"{{ draw }}/cheatsheet.svg"

# initialize the west workspace
[group('workspace')]
init:
    west init -l config
    west update --fetch-opt=--filter=blob:none
    west zephyr-export

# synchronize the west workspace (after manifest changes)
[group('workspace')]
sync:
    west update --fetch-opt=--filter=blob:none

# bump nix toolchain (flake.lock)
[group('workspace')]
bump-nix:
    nix flake update --flake .

# clear build cache and artifacts
[group('cleanup')]
clean:
    rm -rf {{ build }} {{ out }}

# garbage-collect the nix store (system-wide)
[group('cleanup')]
nix-gc:
    nix-collect-garbage --delete-old

# format devicetree files, or a single directory recursively
[group('dev')]
[no-cd]
format *paths:
    #!/usr/bin/env bash
    set -euo pipefail
    paths=({{ paths }})

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "Usage: just format <file>... | <dir>" >&2
        exit 1
    fi

    for path in "${paths[@]}"; do
        if [[ -d "$path" ]]; then
            if [[ ${#paths[@]} -gt 1 ]]; then
                echo "A directory must be the only argument. Aborting..." >&2
                exit 1
            fi
            cd "$path"
            dts-format --fix
            exit 0
        fi
    done

    dts-format --fix "${paths[@]}"

# run test suites (--auto-accept updates the snapshot)
[group('dev')]
[no-cd]
test $testpath *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    testcase=$(basename "$testpath")
    build_dir="{{ build / "tests" / '$testcase' }}"
    config_dir=$(realpath "$testpath")
    cd {{ justfile_directory() }}

    if [[ "{{ FLAGS }}" != *"--no-build"* ]]; then
        echo "Running $testcase..."
        rm -rf "$build_dir"
        west build -s zmk/app -d "$build_dir" -b native_sim//zmk_test_mock -- \
            -DCONFIG_ASSERT=y -DZMK_CONFIG="$config_dir"
    fi

    ${build_dir}/zephyr/zmk.exe | sed -e "s/.*> //" |
        tee ${build_dir}/keycode_events.full.log |
        sed -n -f ${config_dir}/events.patterns > ${build_dir}/keycode_events.log
    if [[ "{{ FLAGS }}" == *"--verbose"* ]]; then
        cat ${build_dir}/keycode_events.log
    fi

    if [[ "{{ FLAGS }}" == *"--auto-accept"* ]]; then
        cp ${build_dir}/keycode_events.log ${config_dir}/keycode_events.snapshot
    fi
    diff -auZ ${config_dir}/keycode_events.snapshot ${build_dir}/keycode_events.log

# warn user if they are using golang-yq and not python-yq
[no-exit-message]
_check_yq_version:
    #!/usr/bin/env bash
    if yq --help 2>&1 | grep -qi 'eval'; then
        echo "This script requires python-yq, but PATH contains golang-yq" >&2
        echo "Please install python-yq or use the included nix shell" >&2
        exit 1
    fi
