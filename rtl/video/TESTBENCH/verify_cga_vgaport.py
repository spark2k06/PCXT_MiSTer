#!/usr/bin/env python3
"""Compare the streaming FPGA decoder with the x86EMU/UniPCemu equations."""

from __future__ import annotations

import csv
import math
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
RTL = ROOT / "rtl" / "video" / "cga_vgaport.v"
SAMPLES = ROOT / "rtl" / "video" / "TESTBENCH" / "cga_vgaport_samples.csv"

INTENSITY = (77.175381, 88.654656, 166.564623, 174.228438)


def load_chroma_table() -> list[int]:
    text = RTL.read_text(encoding="utf-8")
    entries = {
        int(index): int(value)
        for index, value in re.findall(
            r"chroma_multiplexer\[\s*(\d+)\]\s*=\s*(\d+)", text
        )
    }
    if set(entries) != set(range(256)):
        raise AssertionError("RTL chroma table does not contain exactly 256 entries")
    return [entries[index] for index in range(256)]


CHROMA = load_chroma_table()


def build_voltage_table(bw: bool) -> list[int]:
    minimum = CHROMA[0] + INTENSITY[0]
    maximum = CHROMA[255] + INTENSITY[3]

    base_contrast = 256.0 / (maximum - minimum)
    contrast = base_contrast
    brightness = -minimum * base_contrast

    table: list[int] = []
    for address in range(1024):
        phase = address & 3
        right = (address >> 2) & 15
        left = (address >> 6) & 15
        lc = ((left & 8) | (7 if left & 7 else 0)) if bw else left
        rc = ((right & 8) | (7 if right & 7 else 0)) if bw else right
        c = CHROMA[((lc & 7) << 5) | ((rc & 7) << 2) | phase]
        i = INTENSITY[(left >> 3) | ((right >> 2) & 2)]
        voltage = c + i
        table.append(int(voltage * contrast + brightness))
    return table


def coefficients(table: list[int], text_80_column: bool) -> tuple[int, ...]:
    calibration_i = table[6 * 68] - table[6 * 68 + 2]
    calibration_q = table[6 * 68 + 1] - table[6 * 68 + 3]
    # UniPCemu applies 14 degrees in 80-column text and 4 otherwise.
    mode_hue = 14 if text_80_column else 4
    angle = 2.0 * math.pi * (33 + 90 + mode_hue) / 360.0
    c = math.cos(angle)
    s = math.sin(angle)
    saturation = 2.9
    scale = 256.0 * saturation / math.sqrt(
        calibration_i * calibration_i + calibration_q * calibration_q
    )
    adjust_i = -(calibration_i * c + calibration_q * s) * scale
    adjust_q = (calibration_q * c - calibration_i * s) * scale
    return (
        int(0.9563 * adjust_i + 0.6210 * adjust_q),
        int(-0.9563 * adjust_q + 0.6210 * adjust_i),
        int(-0.2721 * adjust_i - 0.6474 * adjust_q),
        int(0.2721 * adjust_q - 0.6474 * adjust_i),
        int(-1.1069 * adjust_i + 1.7046 * adjust_q),
        int(1.1069 * adjust_q + 1.7046 * adjust_i),
    )


def clamp6(value: int) -> int:
    byte = value >> 13
    byte = max(0, min(255, byte))
    return byte >> 2


def decode_reference(
    pixels: list[int], bw: bool, highres: bool,
    text_80_column: bool,
    burst_gain: int = 15, phase_bit: int = 0,
) -> list[tuple[int, int, int]]:
    table = build_voltage_table(bw)
    coeff_ri, coeff_rq, coeff_gi, coeff_gq, coeff_bi, coeff_bq = coefficients(
        table, text_80_column
    )

    def pixel(index: int) -> int:
        return pixels[index] if 0 <= index < len(pixels) else 0

    def wave(index: int) -> int:
        return table[(pixel(index) << 6) | (pixel(index + 1) << 2) | (index & 3)]

    result: list[tuple[int, int, int]] = []
    for k in range(len(pixels)):
        if bw or burst_gain == 0:
            y = ((wave(k) * 2 + wave(k - 1) + wave(k + 1)) << 3) << 8
            gray = clamp6(y)
            result.append((gray, gray, gray))
            continue

        def a(center: int) -> int:
            return (
                wave(center - 4)
                - 2 * (wave(center - 2) - wave(center) + wave(center + 2))
                + wave(center + 4)
            )

        chroma_a = a(k)
        chroma_b = 2 * (
            wave(k - 3) - wave(k - 1) + wave(k + 1) - wave(k + 3)
        )
        filtered_prev = 8 * wave(k - 1) - a(k - 1)
        filtered_center = 8 * wave(k) - chroma_a
        filtered_next = 8 * wave(k + 1) - a(k + 1)
        y = (2 * filtered_center + filtered_prev + filtered_next) << 8

        # The streaming sample phase already follows the native CGA dot
        # sequence.  High-resolution text only applies the CRTC calibration
        # phase bit; an extra half-cycle rotation would swap the decoded
        # colour quadrants.
        phase = (k + phase_bit) & 3
        i, q = (
            (chroma_a, chroma_b),
            (-chroma_b, chroma_a),
            (-chroma_a, -chroma_b),
            (chroma_b, -chroma_a),
        )[phase]
        if burst_gain == 4:
            i, q = i >> 2, q >> 2
        elif burst_gain == 8:
            i, q = i >> 1, q >> 1
        elif burst_gain == 12:
            i, q = i - (i >> 2), q - (q >> 2)
        result.append(
            (
                clamp6(y + coeff_ri * i + coeff_rq * q),
                clamp6(y + coeff_gi * i + coeff_gq * q),
                clamp6(y + coeff_bi * i + coeff_bq * q),
            )
        )
    return result


def main() -> None:
    cases: dict[tuple[int, int, int, int, int, int], list[dict[str, int]]] = defaultdict(list)
    with SAMPLES.open(newline="", encoding="utf-8") as stream:
        for raw in csv.DictReader(stream):
            row = {key: int(value) for key, value in raw.items()}
            cases[(
                row["bw"], row["hres"], row["grph"],
                row["hsync_width"], row["border"], row["phase"]
            )].append(row)

    expected_cases = {
        (0, 0, 1, 10, 0, 0),
        (1, 0, 1, 10, 0, 0),
        (0, 0, 0, 10, 0, 0),
        (0, 1, 1, 10, 0, 0),
        (0, 1, 1, 10, 0, 1),
        (0, 1, 0, 15, 0, 0),
        (0, 1, 0, 10, 0, 0),
        (0, 1, 0, 13, 0, 1),
        (0, 1, 0, 14, 0, 0),
        (0, 1, 0, 14, 0, 1),
        (0, 1, 0, 10, 1, 0),
    }
    if set(cases) != expected_cases:
        raise AssertionError(f"Unexpected simulation cases: {sorted(cases)}")

    summaries = []
    for (bw, hres, grph, hsync_width, border, phase), rows in sorted(cases.items()):
        pixels = [row["input"] for row in rows]
        text_80_column = bool(hres and not grph)
        burst_present = (
            (not text_80_column)
            or hsync_width in (0, 15)
            or (hsync_width == 14 and bool(phase))
        )
        burst_gain = 15 if burst_present else 0
        reference = decode_reference(
            pixels, bool(bw), bool(hres), text_80_column,
            burst_gain=burst_gain,
            phase_bit=phase,
        )
        mode_name = "text80" if text_80_column else ("graphics" if grph else "text40")
        errors = []
        color_spreads = []

        # The filter/matrix pipeline adds two samples to the six-sample
        # streaming decoder latency.
        for x in range(20, len(rows) - 12):
            actual = (rows[x]["r"], rows[x]["g"], rows[x]["b"])
            expected = reference[x - 8]
            errors.extend(abs(a - e) for a, e in zip(actual, expected))
            color_spreads.append(max(actual) - min(actual))

        mae = sum(errors) / len(errors)
        maximum = max(errors)
        average_spread = sum(color_spreads) / len(color_spreads)
        # Samples 70..95 correspond to two-sample-wide white/black strokes
        # after the six-pixel streaming latency. This is the carrier-relative
        # pattern that gives BIOS/MS-DOS text its colored composite fringes.
        boot_text_spread = sum(
            max(rows[x]["r"], rows[x]["g"], rows[x]["b"])
            - min(rows[x]["r"], rows[x]["g"], rows[x]["b"])
            for x in range(70, 96)
        ) / 26.0
        summaries.append(
            f"bw={bw} mode={mode_name} hsync={hsync_width:X} border={border:X} "
            f"phase={phase} gain={burst_gain}: "
            f"MAE={mae:.3f}/63 max={maximum}/63 spread={average_spread:.2f}"
            f" boot-text-spread={boot_text_spread:.2f}"
        )

        if mae > 1.25 or maximum > 8:
            raise AssertionError(summaries[-1] + " (fixed-point error too large)")
        if (bw or not burst_present) and any(
            not (row["r"] == row["g"] == row["b"]) for row in rows[18:-12]
        ):
            raise AssertionError("B&W mode produced chroma")
        if not bw and burst_present and average_spread < 7.0:
            raise AssertionError("Color-burst mode lost chroma")
        if text_80_column and not bw and burst_present and boot_text_spread < 20.0:
            raise AssertionError("80-column boot text lost composite color fringes")

    print("PASS: fixed-point decoder follows the UniPCemu reference")
    for summary in summaries:
        print(summary)


if __name__ == "__main__":
    main()
