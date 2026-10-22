# submoduletags

A quick way to see what release each git submodule is on, and when the parent repository last moved it.

## Purpose

Repositories with many nested submodules make it tedious to answer "which version is this component at?". This tool answers that for the whole tree at once.

## What it does

- Walks a repository and every nested submodule
- Fetches each submodule so tag information is current
- Lists the tags on the commit each submodule is checked out at, in alphabetical or reverse order
- Shows the history of parent-repository commits that changed a submodule's pinned commit, optionally annotated with parent-repository tags
- Narrows results to a subset of submodules and limits how far back history goes
- Produces colorized output for people and stable tab-separated output for scripts

## What it does not do

- Change what is checked out or update submodule pointers
- Report branches; it works with tags and commits only

## Requirements

- Bash
- Git
