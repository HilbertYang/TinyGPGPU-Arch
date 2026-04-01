#!/usr/bin/env python3
"""Convert between BF16 hex values and decimal numbers."""

from __future__ import annotations

import argparse
import math
import struct
import sys


def normalize_bf16_token(token: str) -> str:
    normalized = token.strip().lower().replace("_", "")

    if normalized.startswith("16'h"):
        normalized = normalized[4:]
    elif normalized.startswith("'h"):
        normalized = normalized[2:]

    if normalized.startswith("0x"):
        normalized = normalized[2:]

    if not normalized:
        raise ValueError("empty BF16 value")

    if len(normalized) > 4:
        raise ValueError(f"'{token}' is longer than 16 bits")

    value = int(normalized, 16)
    return f"{value:04x}"


def bf16_to_float(token: str) -> float:
    bf16_bits = int(normalize_bf16_token(token), 16)
    fp32_bits = bf16_bits << 16
    return struct.unpack(">f", struct.pack(">I", fp32_bits))[0]


def float_to_float32_bits(value: float) -> int:
    if math.isnan(value):
        return 0x7FC00000

    if math.isinf(value):
        return 0x7F800000 if value > 0 else 0xFF800000

    try:
        return struct.unpack(">I", struct.pack(">f", value))[0]
    except OverflowError:
        return 0x7F800000 if value > 0 else 0xFF800000


def float_to_bf16_bits(value: float) -> int:
    fp32_bits = float_to_float32_bits(value)
    exponent = fp32_bits & 0x7F800000
    mantissa = fp32_bits & 0x007FFFFF

    if exponent == 0x7F800000:
        if mantissa:
            return ((fp32_bits >> 16) | 0x0040) & 0xFFFF
        return (fp32_bits >> 16) & 0xFFFF

    round_bias = 0x7FFF + ((fp32_bits >> 16) & 1)
    return ((fp32_bits + round_bias) >> 16) & 0xFFFF


def parse_decimal_token(token: str) -> float:
    normalized = token.strip().lower().replace("_", "")
    return float(normalized)


def format_decimal(value: float) -> str:
    if math.isnan(value):
        return "nan"

    if math.isinf(value):
        return "inf" if value > 0 else "-inf"

    return format(value, ".9g")


def read_tokens(values: list[str]) -> list[str]:
    if values:
        return values

    if sys.stdin.isatty():
        raise ValueError("provide at least one value or pipe data through stdin")

    piped_tokens = sys.stdin.read().split()
    if not piped_tokens:
        raise ValueError("stdin did not contain any values")

    return piped_tokens


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert BF16 hex values and decimal numbers."
    )
    direction = parser.add_mutually_exclusive_group(required=True)
    direction.add_argument(
        "--to-dec",
        action="store_true",
        help="interpret inputs as BF16 hex and print decimal values",
    )
    direction.add_argument(
        "--to-bf16",
        action="store_true",
        help="interpret inputs as decimal values and print BF16 hex",
    )
    parser.add_argument(
        "values",
        nargs="*",
        help="values to convert; accepts multiple items or piped stdin",
    )
    parser.add_argument(
        "--plain",
        action="store_true",
        help="print only converted values, one per line",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        tokens = read_tokens(args.values)
    except ValueError as exc:
        parser.error(str(exc))

    for token in tokens:
        try:
            if args.to_dec:
                normalized = normalize_bf16_token(token)
                converted = format_decimal(bf16_to_float(normalized))
                output = converted if args.plain else f"{normalized} -> {converted}"
            else:
                decimal_value = parse_decimal_token(token)
                converted = f"{float_to_bf16_bits(decimal_value):04x}"
                output = converted if args.plain else f"{token} -> {converted}"

            print(output)
        except ValueError as exc:
            print(f"{token} -> ERROR: {exc}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
