#!/usr/bin/env bash
# Dừng khi lệnh lỗi (-e), biến chưa khai báo (-u), hoặc một lệnh trong pipeline lỗi.
set -euo pipefail
# Mọi đường dẫn bên dưới được tính từ thư mục gốc repo Git.
cd "$(git rev-parse --show-toplevel)"
# Ghi nhớ có lỗi hay không; vẫn xử lý các image còn lại khi phù hợp.
status=0
rm -rf .ci-docker
# Có thể build đã lỗi trước khi tạo danh sách; chỉ cleanup khi file tồn tại.
if [[ -f .ci-images ]]; then
  while read -r image; do
    # Image chưa build xong có thể chưa tồn tại; chỉ xóa tag đang có.
    if docker image inspect "$image" >/dev/null 2>&1; then
      # Chỉ xóa tag của build này; ghi nhận lỗi để Jenkins báo cleanup chưa xong.
      docker image rm "$image" || status=1
    fi
  done < .ci-images
fi
exit "$status"
