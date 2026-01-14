default:
    @just --list --unsorted

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')

# parse build.yaml and filter targets by expression
_parse_targets $expr:
    #!/usr/bin/env bash
    attrs="[.board, .shield, .snippet, .\"cmake-args\", .\"artifact-name\"]"
    filter="(($attrs | map(. // [.]) | combinations), ((.include // {})[] | $attrs)) | join(\",\")"
    echo "$(yq -r "$filter" build.yaml | grep -v "^," | grep -i "${expr/#all/.*}")"

# build firmware for single board & shield combination
_build_single $board $shield $snippet $cmake_args $artifact *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board}}"
    build_dir="{{ build / '$artifact' }}"
    # Expand cmake_args to handle ${PWD} and similar
    cmake_args_expanded=$(eval echo "$cmake_args")

    echo "Building firmware for $artifact..."
    west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
        -DZMK_CONFIG="{{ config }}" ${shield:+-DSHIELD="$shield"} ${cmake_args_expanded}

    if [[ -f "$build_dir/zephyr/zmk.uf2" ]]; then
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.uf2" "{{ out }}/$artifact.uf2"
    else
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.bin" "{{ out }}/$artifact.bin"
    fi

# build firmware for matching targets
build expr *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet cmake_args artifact; do
        just _build_single "$board" "$shield" "$snippet" "$cmake_args" "$artifact" {{ west_args }}
    done

# clear build cache and artifacts
clean:
    rm -rf {{ build }} {{ out }}

# clear all automatically generated files
clean-all: clean
    rm -rf .west zmk

# clear nix cache
clean-nix:
    nix-collect-garbage --delete-old

# parse & plot keymap (3x6+3 split = 42 keys)
draw:
    #!/usr/bin/env bash
    set -euo pipefail
    # Parse keymap
    keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/base.keymap" \
        --virtual-layers Combos >"{{ draw }}/base.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/base.yaml"
    # Rename Sys layer to show it's a conditional layer (FUN + NUM)
    yq -Yi '.layers = (.layers | to_entries | map(if .key == "Sys" then .key = "Sys (FUN + NUM)" else . end) | from_entries)' "{{ draw }}/base.yaml"
    # Reorder layers: Num/Sym/Combos after Base, Nav/Fun, then alternates, then extras
    yq -Yi '.layers = {Base: .layers.Base, Num: .layers.Num, Sym: .layers.Sym, Combos: .layers.Combos, Nav: .layers.Nav, Fun: .layers.Fun, Qwerty: .layers.Qwerty, Game: .layers.Game, Gnum: .layers.Gnum, Mouse: .layers.Mouse, Numpad: .layers.Numpad, Intl: .layers.Intl, "Sys (FUN + NUM)": .layers."Sys (FUN + NUM)", Media: .layers.Media}' "{{ draw }}/base.yaml"
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
    yq -Yi '.layers.Media[18] = {type: "held"}' "{{ draw }}/base.yaml"
    # Set 2-column layout
    yq -Yi '.draw_config.n_columns = 2' "{{ draw }}/base.yaml"
    # Draw with physical layout from Toucan shield DTS
    keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/base.yaml" \
        -d "zmk-keyboard-toucan/boards/shields/toucan/toucan.dtsi" >"{{ draw }}/base.svg"

# generate minimal cheatsheet (Base, Num, Sym + Combos) in 2x2 grid
cheatsheet:
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

# initialize west
init:
    west init -l config
    west update --fetch-opt=--filter=blob:none
    west zephyr-export

# list build targets
list:
    @just _parse_targets all | sed 's/,*$//' | sort | column

# update west
update:
    west update --fetch-opt=--filter=blob:none

# upgrade zephyr-sdk and python dependencies
upgrade-sdk:
    nix flake update --flake .

[no-cd]
test $testpath *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    testcase=$(basename "$testpath")
    build_dir="{{ build / "tests" / '$testcase' }}"
    config_dir="{{ '$(pwd)' / '$testpath' }}"
    cd {{ justfile_directory() }}

    if [[ "{{ FLAGS }}" != *"--no-build"* ]]; then
        echo "Running $testcase..."
        rm -rf "$build_dir"
        west build -s zmk/app -d "$build_dir" -b native_posix_64 -- \
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
