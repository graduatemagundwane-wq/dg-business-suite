"""Bundle the reviewed PASH Operations source for the legacy Render QA build."""
from pathlib import Path
import base64
import io
import zipfile

root = Path("pash-operations/app")
archive = Path("pash-operations/source-v0.5.0.zip.b64")
paths = sorted(p for p in root.rglob("*") if p.is_file() and (
    p.relative_to(root).parts[0] in {"backend", "mobile", "web"}
    or p.relative_to(root).as_posix() in {"Dockerfile", "render.yaml"}
) and "__pycache__" not in p.parts and "node_modules" not in p.parts)
assert len(paths) >= 39, f"Expected complete ERP sources, found {len(paths)}"
required = {"backend/main.py", "backend/models.py", "backend/advanced.py",
            "backend/migrations/006_attendance_approvals.sql", "mobile/App.tsx",
            "web/index.html", "web/app.js"}
assert required.issubset({p.relative_to(root).as_posix() for p in paths})
output = io.BytesIO()
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in paths:
        z.write(path, arcname=path.relative_to(root).as_posix())
raw = output.getvalue()
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert required.issubset(z.namelist())
assert len(raw) < 2_000_000, "Unexpectedly large source bundle"
archive.write_text(base64.b64encode(raw).decode("ascii") + "\n")
print(f"Rebuilt {archive} with {len(paths)} source files; ZIP {len(raw)} bytes")

# Android QA stability revision 20261103
