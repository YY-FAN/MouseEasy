#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
probe_dir="$(mktemp -d /tmp/wheelease-key-layout.XXXXXX)"
module_dir="$project_dir/build/local/modules"
sdk_dir="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[[ -d "$sdk_dir" ]] || sdk_dir="$(xcrun --show-sdk-path)"
swiftc -swift-version 5 -parse-as-library -sdk "$sdk_dir" -module-cache-path "$probe_dir/cache" \
  -I "$module_dir" -I "$module_dir/KeyKitC" -L "$module_dir" -lKeyKit \
  -Xlinker -rpath -Xlinker "$module_dir" \
  "$project_dir/LinearMouse/EventTap/EventThread.swift" \
  "$project_dir/LocalTests/KeyLayoutThreadingProbe.swift" -o "$probe_dir/probe"
"$probe_dir/probe"
