# korad

A terminal front panel for single-channel programmable Korad bench power supplies.

## Purpose

Monitor and control a Korad supply from a terminal, including over ssh or on a headless machine, without vendor desktop software.

## What it does

- Shows the set and actual voltage and current in a live display
- Accepts supply commands typed into an input box, with the available commands listed on screen
- Talks to the supply over its serial (USB) connection
- Runs on Windows, Linux, and macOS

## What it does not do

- Support multi-channel supplies; it targets single-channel models

## Requirements

- Python 3
- `pyserial` and `rich`
- `pywin32` on Windows
- A Korad supply connected over a serial port
