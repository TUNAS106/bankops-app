#!/usr/bin/env bash
# Dừng khi lệnh lỗi (-e), biến chưa khai báo (-u), hoặc một lệnh trong pipeline lỗi.
set -euo pipefail
# Mọi đường dẫn bên dưới được tính từ thư mục gốc repo Git.
cd "$(git rev-parse --show-toplevel)"
ROOT=$PWD
# Biến bắt buộc: dừng sớm và báo rõ nếu người gọi chưa cung cấp.
: "${DOCKERHUB_NAMESPACE:?Missing namespace}"
# Biến bắt buộc: dừng sớm và báo rõ nếu người gọi chưa cung cấp.
: "${IMAGE_TAG:?Missing tag}"
# Tạo nơi lưu bằng chứng để Jenkins có thể hiển thị/tải về sau build.
mkdir -p reports
# Làm rỗng danh sách tag cần cleanup, kể cả khi build dừng giữa chừng.
: > .ci-images
# Danh sách riêng chỉ chứa image đã build thành công để scan/push.
: > .ci-built-images
# Tạo mới báo cáo cho lần chạy này, không nối vào kết quả cũ.
: > reports/local-images.tsv
# Chọn JDK 17 cho build app trong script; Jenkins service vẫn dùng Java 21.
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

# Đọc mỗi dòng images.tsv thành ba biến: tên service, cách build, thư mục.
# Vẫn xử lý dòng cuối nếu file danh sách thiếu ký tự xuống dòng.
while read -r service builder source_dir || [[ -n "${service:-}" ]]; do
  # Ghép tên Docker Hub với tag do Jenkins tạo từ commit SHA và số build.
  image="$DOCKERHUB_NAMESPACE/bankops-$service:$IMAGE_TAG"
  printf '%s\n' "$image" >> .ci-images
  if [[ "$builder" == docker ]]; then
    # Build từ Dockerfile; thư mục cuối lệnh là build context.
    docker build --platform linux/amd64 --pull -t "$image" "$source_dir"
  elif [[ "$builder" == jib ]]; then
  # Subshell: cd bên trong không đổi thư mục của vòng lặp bên ngoài.
    (
      cd "$ROOT/$source_dir"
      # Jib tạo image vào Docker local; unit test đã chạy ở stage quality.
      bash "$ROOT/mvnw" -B -ntp compile jib:dockerBuild -Dimage="$image"
    )
  else
    echo "Unknown builder: $builder" >&2
    exit 1
  fi
  printf '%s\n' "$image" >> .ci-built-images
  # Lưu định danh image local để đối chiếu artifact của lần build.
  image_id=$(docker image inspect --format '{{.Id}}' "$image")
  printf '%s\t%s\t%s\n' "$service" "$image" "$image_id" >> reports/local-images.tsv
done < scripts/ci/images.tsv
