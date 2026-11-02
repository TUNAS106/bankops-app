#!/usr/bin/env bash
# Dừng khi lệnh lỗi (-e), biến chưa khai báo (-u), hoặc một lệnh trong pipeline lỗi.
set -euo pipefail
# Tìm thư mục gốc repo để chạy đúng dù gọi script từ thư mục con.
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
# Tạo nơi lưu bằng chứng để Jenkins có thể hiển thị/tải về sau build.
mkdir -p reports

# Lần lượt kiểm tra ba service Python, tránh chạy song song tốn RAM.
for service_dir in src/frontend src/accounts/userservice src/accounts/contacts; do
  # Subshell: cd bên trong không đổi thư mục của vòng lặp bên ngoài.
  (
    cd "$ROOT/$service_dir"
    # Cài dependency; --locked báo lỗi nếu pyproject.toml và uv.lock lệch nhau.
    uv sync --locked --python 3.14 --group dev
    # Kiểm tra code theo quy tắc chung trong .pylintrc của repo.
    uv run --locked pylint --rcfile="$ROOT/.pylintrc" ./*.py
    # Frontend hiện chưa có unit test suite; hai service còn lại chạy pytest.
    if [[ "$service_dir" != src/frontend ]]; then
      mkdir -p reports
      # XML là báo cáo để Jenkins hiển thị từng test case.
      uv run --locked pytest tests/ -v --junitxml=reports/junit.xml
    fi
  )
done

# Chọn JDK 17 cho build app trong script; Jenkins service vẫn dùng Java 21.
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
# Chạy Maven trong từng module để tìm đúng checkstyle.xml.
for service in ledgerwriter balancereader transactionhistory; do
  # Subshell: cd bên trong không đổi thư mục của vòng lặp bên ngoài.
  (
    cd "$ROOT/src/ledger/$service"
    # verify chạy compile/test/package; checkstyle:check kiểm tra style Java.
    bash "$ROOT/mvnw" -B -ntp clean verify checkstyle:check
  )
done
