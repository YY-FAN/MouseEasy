#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
task_build_dir="$(mktemp -d /tmp/mouse-common-actions.XXXXXX)"
# Compile the actual pure Key enum, with Foundation needed by its String labels.
{ print 'import Foundation'; cat Modules/KeyKit/Sources/KeyKit/Key.swift; } > "$task_build_dir/Key.swift"
swiftc -module-cache-path "$task_build_dir/cache" -emit-library -emit-module \
  -module-name KeyKit -emit-module-path "$task_build_dir/KeyKit.swiftmodule" \
  "$task_build_dir/Key.swift" -o "$task_build_dir/libKeyKit.dylib"
swiftc -module-cache-path "$task_build_dir/cache" \
  -I "$task_build_dir" -L "$task_build_dir" -lKeyKit \
  -Xlinker -rpath -Xlinker "$task_build_dir" \
  LinearMouse/Model/Actions/CommonActionCatalog.swift LocalTests/CommonActionCatalogTests.swift \
  -o "$task_build_dir/validate-common-actions"
"$task_build_dir/validate-common-actions"
