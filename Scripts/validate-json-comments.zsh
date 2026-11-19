#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
task_build_dir="$(mktemp -d /tmp/mouse-json-comments.XXXXXX)"
swiftc -module-cache-path "$task_build_dir/cache" \
  LinearMouse/Utilities/JSONCommentSanitizer.swift \
  LocalTests/JSONCommentSanitizerTests.swift \
  -o "$task_build_dir/validate-json-comments"
"$task_build_dir/validate-json-comments"
