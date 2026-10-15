import ast
import io
import re
import sys
import tokenize
from pathlib import Path

ALLOWED = (
    "fixes bug(",
    "lazy implementation. will fix later :)",
    "not fully functional. ",
    "look at ",
)
SUFFIXES = {".py": "py", ".gd": "gd", ".gdshader": "gd", ".gdshaderinc": "gd", ".sh": "sh", ".js": "js"}


def allowed(text):
    body = text.lstrip("#/ ").strip()
    return body.startswith(ALLOWED)


def py_findings(src):
    out = []
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.ClassDef, ast.AsyncFunctionDef)):
            body = node.body
            if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
                out.append(("doc", body[0].lineno, body[0].end_lineno))
    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == tokenize.COMMENT and not tok.string.startswith("#!") and not allowed(tok.string):
            out.append(("comment", tok.start[0], tok.start[1]))
    return out


def tidy(text):
    text = re.sub(r"(:[ \t]*)\n[ \t]*\n(?=[ \t]+\S)", r"\1\n", text)
    return re.sub(r"\n(?:[ \t]*\n){3,}", "\n\n\n", text)


def py_fix(src):
    lines = src.split("\n")
    kill = set()
    cuts = []
    for kind, a, b in py_findings(src):
        if kind == "doc":
            kill.update(range(a, b + 1))
        else:
            cuts.append((a, b))
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.ClassDef, ast.AsyncFunctionDef)):
            body = node.body
            if len(body) == 1 and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str) and not isinstance(node, ast.Module):
                ind = " " * body[0].col_offset
                lines[body[0].lineno - 1] = ind + "pass"
                kill.difference_update(range(body[0].lineno, body[0].end_lineno + 1))
                kill.update(range(body[0].lineno + 1, body[0].end_lineno + 1))
    for ln, col in cuts:
        if ln in kill:
            continue
        lines[ln - 1] = lines[ln - 1][:col].rstrip()
    out = [l for i, l in enumerate(lines, 1) if i not in kill]
    return tidy("\n".join(out))


def scan_line(line, marker):
    q = None
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif line.startswith(marker, i) and not (marker == "//" and i > 0 and line[i - 1] == ":"):
            return i
        i += 1
    return -1


def line_findings(src, marker):
    out = []
    in_block = False
    for n, line in enumerate(src.split("\n"), 1):
        if marker == "//" and "/*" in line:
            in_block = True
        if in_block:
            out.append((n, 0))
            if "*/" in line:
                in_block = False
            continue
        i = scan_line(line, marker)
        if i < 0:
            continue
        if marker == "#" and n == 1 and line.startswith("#!"):
            continue
        text = line[i:]
        if not allowed(text):
            out.append((n, i))
    return out


def process(path, fix):
    kind = SUFFIXES.get(path.suffix)
    if kind is None:
        return []
    src = path.read_text()
    if kind == "py":
        found = py_findings(src)
        if fix:
            new = py_fix(src) if found else tidy(src)
            if new != src:
                path.write_text(new)
        return [(path, a, k) for k, a, _ in found]
    marker = "//" if path.suffix in (".gdshader", ".gdshaderinc", ".js") else "#"
    found = line_findings(src, marker)
    if fix and not found:
        if tidy(src) != src:
            path.write_text(tidy(src))
    if found and fix:
        lines = src.split("\n")
        drop = set()
        for n, col in found:
            before = lines[n - 1][:col].rstrip()
            if before.strip() == "":
                drop.add(n)
            else:
                lines[n - 1] = before
        res = "\n".join(l for i, l in enumerate(lines, 1) if i not in drop)
        path.write_text(tidy(res))
    return [(path, n, "comment") for n, _ in found]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fix = "--fix" in sys.argv
    if not args:
        sys.exit("usage: check_notes.py [--fix] <file or dir>...")
    bad = []
    for a in args:
        p = Path(a)
        if not p.exists():
            print(f"{a}: no such file or directory", file=sys.stderr)
            sys.exit(2)
        files =[p] if p.is_file() else sorted(q for q in p.rglob("*") if q.is_file() and ".godot" not in q.parts)
        for f in files:
            bad += process(f, fix)
    for path, n, kind in bad:
        print(f"{path}:{n}: {kind}")
    print(("fixed " if fix else "found ") + str(len(bad)))
    sys.exit(0 if fix or not bad else 1)


if __name__ == "__main__":
    main()
