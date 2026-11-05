#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
# Jenkins chạy select-services.py trước để tạo danh sách của riêng lần build.
selection=reports/selected-services.tsv
test -f "$selection"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

while read -r service builder source_dir || [[ -n "${service:-}" ]]; do
  echo "=== Quality: $service ==="
  if [[ "$builder" == jib ]]; then
    (
      cd "$ROOT/$source_dir"
      # Chạy trong module để tìm đúng checkstyle.xml. verify gồm unit test.
      bash "$ROOT/mvnw" -B -ntp clean verify checkstyle:check
    )
  elif [[ "$service" == frontend || "$service" == userservice || "$service" == contacts ]]; then
    (
      cd "$ROOT/$source_dir"
      uv sync --locked --python 3.14 --group dev
      uv run --locked pylint --rcfile="$ROOT/.pylintrc" ./*.py
      # Frontend chưa có unit test suite trong source hiện tại.
      if [[ "$service" != frontend ]]; then
        mkdir -p reports
        uv run --locked pytest tests/ -v --junitxml=reports/junit.xml
      fi
    )
  else
    # Hai database hiện chỉ có bước build và scan, chưa có unit test suite.
    echo "No unit test suite configured for $service"
  fi
done < "$selection"
