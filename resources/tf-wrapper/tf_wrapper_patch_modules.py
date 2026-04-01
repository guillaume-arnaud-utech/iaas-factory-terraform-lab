#!/usr/bin/env python3

import argparse
import os
import re
from typing import List, Tuple


MODULE_START_RE = re.compile(r'^(?P<indent>\s*)module\s+"(?P<name>[^"]+)"\s*\{')
LABELS_RE = re.compile(r'^(?P<indent>\s*)labels\s*=\s*(?P<expr>.+?)\s*(#.*)?$')
SOURCE_RE = re.compile(r'^\s*source\s*=\s*(?P<expr>.+?)\s*(#.*)?$')
INSTANCE_BASE_NAME_RE = re.compile(r'^(?P<indent>\s*)instance_base_name\s*=\s*(?P<expr>.+?)\s*(#.*)?$')


def brace_delta(line: str) -> int:
    return line.count("{") - line.count("}")


def find_module_blocks(lines: List[str]) -> List[Tuple[int, int]]:
    blocks = []
    i = 0
    while i < len(lines):
        if MODULE_START_RE.match(lines[i]):
            start = i
            depth = brace_delta(lines[i])
            i += 1
            while i < len(lines) and depth > 0:
                depth += brace_delta(lines[i])
                i += 1
            blocks.append((start, i))
        else:
            i += 1
    return blocks


def module_matches(block: List[str], source_contains: str) -> bool:
    return any(source_contains in line for line in block)


def choose_indent(block: List[str], fallback_indent: str) -> str:
    for line in block:
        if SOURCE_RE.match(line):
            return re.match(r"^\s*", line).group(0)
    return fallback_indent


def patch_file(
    path: str,
    locals_symbol: str,
    source_contains: str,
    set_instance_base_name: bool,
    instance_base_name: str,
    instance_base_name_module_source_contains: str,
) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    if not text.strip():
        return False

    lines = text.splitlines(keepends=True)
    changed = False

    for start, end in reversed(find_module_blocks(lines)):
        block = lines[start:end]
        if not module_matches(block, source_contains):
            continue

        if set_instance_base_name and module_matches(block, instance_base_name_module_source_contains):
            instance_idx = -1
            instance_match = None
            for idx, line in enumerate(block):
                m = INSTANCE_BASE_NAME_RE.match(line)
                if m:
                    instance_idx = idx
                    instance_match = m
                    break

            if instance_idx >= 0 and instance_match:
                indent = instance_match.group("indent")
                desired_line = f'{indent}instance_base_name = "{instance_base_name}"\n'
                if block[instance_idx] != desired_line:
                    block[instance_idx] = desired_line
                    lines[start:end] = block
                    changed = True
            else:
                insert_at = end - 1
                for i in range(end - 1, start, -1):
                    if re.match(r"^\s*\}\s*$", lines[i]):
                        insert_at = i
                        break
                module_indent = re.match(r"^\s*", lines[start]).group(0)
                indent = choose_indent(block, module_indent + "  ")
                lines[insert_at:insert_at] = [f'{indent}instance_base_name = "{instance_base_name}"\n']
                changed = True

            # Refresh local block after potential edition.
            block = lines[start:end]

        labels_idx = -1
        labels_match = None
        for idx, line in enumerate(block):
            m = LABELS_RE.match(line)
            if m:
                labels_idx = idx
                labels_match = m
                break

        if labels_idx >= 0 and labels_match:
            current_line = block[labels_idx]
            if locals_symbol in current_line:
                continue
            indent = labels_match.group("indent")
            expr = labels_match.group("expr").strip()
            block[labels_idx] = f"{indent}labels = merge({expr}, {locals_symbol})\n"
            lines[start:end] = block
            changed = True
            continue

        insert_at = end - 1
        for i in range(end - 1, start, -1):
            if re.match(r"^\s*\}\s*$", lines[i]):
                insert_at = i
                break

        module_indent = re.match(r"^\s*", lines[start]).group(0)
        indent = choose_indent(block, module_indent + "  ")
        lines[insert_at:insert_at] = [f"{indent}labels = {locals_symbol}\n"]
        changed = True

    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write("".join(lines))
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch Terraform module blocks to inject labels.")
    parser.add_argument("--dir", default=".")
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--locals-symbol", default="local.tf_wrapper_labels")
    parser.add_argument("--module-source-contains", default="tf-module-gcp-")
    parser.add_argument("--set-instance-base-name", default="0")
    parser.add_argument("--instance-base-name", default="")
    parser.add_argument("--instance-base-name-module-source-contains", default="tf-module-gcp-ceins")
    args = parser.parse_args()

    root = os.path.abspath(args.dir)
    excluded = set(args.exclude)

    set_instance_base_name = str(args.set_instance_base_name).lower() in {"1", "true", "yes"}
    for name in os.listdir(root):
        if not name.endswith(".tf"):
            continue
        if name in excluded:
            continue
        patch_file(
            os.path.join(root, name),
            locals_symbol=args.locals_symbol,
            source_contains=args.module_source_contains,
            set_instance_base_name=set_instance_base_name,
            instance_base_name=args.instance_base_name,
            instance_base_name_module_source_contains=args.instance_base_name_module_source_contains,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
