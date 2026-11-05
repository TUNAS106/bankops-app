#!/usr/bin/env python3
"""Chọn service cần build bằng git diff; chỉ dùng thư viện chuẩn Python."""
import os
from pathlib import Path
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args])


os.chdir(git("rev-parse", "--show-toplevel").decode().strip())
reports = Path("reports")
reports.mkdir(exist_ok=True)
# images.tsv vẫn là danh sách toàn bộ service. Không chỉnh file này mỗi build.
rows = [line.split() for line in Path("scripts/ci/images.tsv").read_text().splitlines()
        if line.strip()]
for row in rows:
    if len(row) != 3:
        raise ValueError("Each images.tsv row must have: service builder source_dir")

head = git("rev-parse", "HEAD").decode().strip()
base = os.environ.get("BASE_COMMIT", "")
force_all = os.environ.get("FORCE_ALL", "false").lower() == "true"
reason = "Changes since previous successful build"
changed = []
select_all = force_all or not base
if force_all:
    reason = "FORCE_ALL requested"
elif not base:
    reason = "No previous successful commit: build all services"
else:
    # Nếu history không có baseline hoặc branch bị force-push, ưu tiên build đủ.
    valid = subprocess.run(["git", "merge-base", "--is-ancestor", base, head],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if valid.returncode != 0:
        select_all = True
        reason = "Baseline missing or not an ancestor: build all services"
    else:
        # -z xử lý tên file có khoảng trắng. --no-renames hiển thị cả đường dẫn
        # cũ và mới của file chuyển service, nên cả hai service đều được chọn.
        changed = git("diff", "--name-only", "--no-renames", "-z", base, head).decode().split("\0")
        changed = [path for path in changed if path]

selected = set()
python_services = {name for name, _, source in rows
                   if source in ("src/frontend", "src/accounts/userservice", "src/accounts/contacts")}
java_services = {name for name, builder, _ in rows if builder == "jib"}
for path in changed:
    # CI/config chung ảnh hưởng mọi image: chọn tất cả để kiểm tra pipeline mới.
    if path == "Jenkinsfile" or path.startswith("scripts/ci/"):
        select_all = True
    elif path == "pom.xml" or path in ("mvnw", "mvnw.cmd") or path.startswith(".mvn/"):
        selected.update(java_services)
    elif path == ".pylintrc":
        selected.update(python_services)
    else:
        owners = {name for name, _, source in rows if path.startswith(source + "/")}
        if owners:
            selected.update(owners)
        elif (path.startswith(("docs/", ".github/", "kubernetes-manifests/", "extras/"))
              or path in ("README.md", "LICENSE", ".gitignore")
              or path.endswith(".md")):
            # Chỉ thay tài liệu/config deployment: không tạo image mới.
            pass
        else:
            # File chưa biết phạm vi ảnh hưởng: build tất cả thay vì bỏ sót.
            select_all = True

if select_all:
    selected = {name for name, _, _ in rows}
chosen = [row for row in rows if row[0] in selected]
(reports / "selected-services.tsv").write_text(
    "".join(" ".join(row) + "\n" for row in chosen))
(reports / "changed-files.txt").write_text("".join(path + "\n" for path in changed))
(reports / "selection.txt").write_text(
    f"Base: {base or '(none)'}\nHead: {head}\nReason: {reason}\n"
    f"Selected: {', '.join(row[0] for row in chosen) or '(none)'}\n")
print((reports / "selection.txt").read_text())
