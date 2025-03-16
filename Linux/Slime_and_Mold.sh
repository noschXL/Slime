#!/bin/sh
echo -ne '\033c\033]0;Slime_and_Mold\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Slime_and_Mold.x86_64" "$@"
