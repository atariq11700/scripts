# macro-commander git macros

Extra compare actions for GitLens in VS Code.

## Purpose

Review everything a branch has changed since it diverged, by comparing the working tree against the merge base rather than the branch tip.

## What it does

- Compares the working tree with the merge base of `HEAD` and `origin/master`
- Compares the working tree with the merge base of `HEAD` and a branch you pick
- Uses the repository of the active editor, and asks which workspace folder to use when that is unclear

## What it does not do

- Support a default branch other than `origin/master` in the first macro

## Requirements

- VS Code
- The [Macro Commander](https://marketplace.visualstudio.com/items?itemName=jeff-hykin.macro-commander) and [GitLens](https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens) extensions
- Git
