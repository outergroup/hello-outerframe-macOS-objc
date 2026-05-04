#!/usr/bin/env python3

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-url", required=True, help="Relative or absolute URL to the outerframe bundle root.")
    parser.add_argument("--output", required=True, help="Path to the .outer file to write.")
    parser.add_argument("--data-file", help="Optional payload to append after the bundle URL.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    bundle_url = args.bundle_url.encode("utf-8")
    if len(bundle_url) > 0xFFFF:
        raise SystemExit("bundle URL is too long for the current .outer format")

    payload = bytearray()
    payload.extend(b"OUTR")
    payload.append(0)
    payload.extend(len(bundle_url).to_bytes(2, "little"))
    payload.extend(bundle_url)

    if args.data_file:
        payload.extend(Path(args.data_file).read_bytes())

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(payload)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
