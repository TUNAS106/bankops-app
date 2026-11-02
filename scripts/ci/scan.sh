#!/usr/bin/env bash
# Dừng khi lệnh lỗi (-e), biến chưa khai báo (-u), hoặc một lệnh trong pipeline lỗi.
set -euo pipefail
# Mọi đường dẫn bên dưới được tính từ thư mục gốc repo Git.
cd "$(git rev-parse --show-toplevel)"
# Tạo nơi lưu bằng chứng để Jenkins có thể hiển thị/tải về sau build.
mkdir -p reports/trivy
# Ghi nhớ có lỗi hay không; vẫn xử lý các image còn lại khi phù hợp.
status=0
# Xử lý lần lượt từng image trong danh sách ở cuối vòng lặp.
while read -r image; do
  # Bỏ namespace trước dấu / cuối cùng để lấy tên repository và tag.
  name=${image##*/}
  # Bỏ phần :tag để dùng tên repository làm tên file report.
  name=${name%%:*}
  report="reports/trivy/$name.json"
  # Scan image local; HIGH/CRITICAL hoặc lỗi scanner đều chặn publish.
  if ! trivy image --image-src docker --scanners vuln --no-progress \
      --timeout 15m --severity HIGH,CRITICAL --exit-code 1 \
      --format json --output "$report" "$image"; then
    echo "Scan/gate failed for $image; inspect report and console" >&2
    status=1
  fi
done < .ci-built-images
exit "$status"
