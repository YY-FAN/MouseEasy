#!/bin/zsh
set -eu
cd "${0:A:h:h}"
audit_dir=$(mktemp -d /tmp/mouse-workbench-core.XXXXXX)
swiftc -module-cache-path "$audit_dir/module-cache" \
  LinearMouse/Utilities/AppIdentity.swift \
  LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/OpenTarget.swift \
  LocalTests/Core/main.swift -o "$audit_dir/validate"
"$audit_dir/validate"
