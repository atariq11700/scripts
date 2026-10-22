# dotfiles

A shared bash environment so every machine feels the same.

## Purpose

Keep shell configuration in one place and link it into a home directory, instead of maintaining separate copies per machine.

## What it provides

- A common bash profile
- Per-machine overrides that stay out of the shared profile
- A git-aware prompt, including a variant for Git for Windows
- Git tab completion
- A setup step that links the files into the home directory without overwriting anything already there

## What it does not do

- Manage dotfiles for other shells or tools; it only covers bash

## Requirements

- Bash and Git
- On Windows, Git Bash with permission to create symlinks (developer mode or an elevated shell)

## Licensing

The git prompt and completion scripts come from the Git project and keep their original licenses.
