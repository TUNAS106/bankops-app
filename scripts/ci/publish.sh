#!/usr/bin/env bash
# Dừng khi lệnh lỗi (-e), biến chưa khai báo (-u), hoặc một lệnh trong pipeline lỗi.
set -euo pipefail
# Mọi đường dẫn bên dưới được tính từ thư mục gốc repo Git.
cd "$(git rev-parse --show-toplevel)"
# Biến bắt buộc: dừng sớm và báo rõ nếu người gọi chưa cung cấp.
: "${DH_USER:?Missing Docker Hub username}"
# Biến bắt buộc: dừng sớm và báo rõ nếu người gọi chưa cung cấp.
: "${DH_TOKEN:?Missing Docker Hub token}"
# Biến bắt buộc: dừng sớm và báo rõ nếu người gọi chưa cung cấp.
: "${DOCKERHUB_NAMESPACE:?Missing namespace}"
# Tạo nơi lưu bằng chứng để Jenkins có thể hiển thị/tải về sau build.
mkdir -p reports
# Giữ credential Docker trong thư mục tạm riêng của job.
export DOCKER_CONFIG="$PWD/.ci-docker"
mkdir -p "$DOCKER_CONFIG"
chmod 700 "$DOCKER_CONFIG"
# Luôn xóa credential tạm khi script kết thúc, kể cả khi push lỗi.
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
# Truyền token qua stdin; không đặt token trực tiếp trên command line.
printf '%s' "$DH_TOKEN" | docker login --username "$DH_USER" --password-stdin
# Tạo mới báo cáo cho lần chạy này, không nối vào kết quả cũ.
: > reports/published-images.tsv
# Xử lý lần lượt từng image trong danh sách ở cuối vòng lặp.
while read -r image; do
  # Push chính image đã build và scan; không build lại ở bước này.
  docker push "$image"
  # Bỏ tag để tìm đúng digest mà registry trả về cho repository này.
  repo=${image%:*}
  # Digest xác định nội dung image trên registry để dùng khi triển khai.
  digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" \
    | awk -v prefix="$repo@sha256:" 'index($0,prefix)==1 {print; exit}')
  [[ -n "$digest" ]] || { echo "No registry digest for $image" >&2; exit 1; }
  printf '%s\t%s\n' "$image" "$digest" >> reports/published-images.tsv
done < .ci-built-images
# Bộ BankOps hiện có tám image; chỉ đánh dấu hoàn tất khi push đủ.
[[ $(wc -l < reports/published-images.tsv) -eq 8 ]]
printf 'All 8 images published\n' > reports/publish-complete.txt
