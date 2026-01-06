# mproc

A lightweight, POSIX-compliant shell library for managing multiple background processes with a built-in progress bar. Extracted from [myims](https://github.com/urain39/myims).

## Features

*   **Simple API**: Easy-to-use functions to create pools and dispatch tasks.
*   **Built-in Progress Bar**: Includes an `awk`-based progress bar with ETA calculation and animation.
*   **Safe Variable Handling**: Strict quoting style ensures robustness with filenames containing spaces or special characters.

## Requirements

*   POSIX-compliant shell (`sh`, `dash`, `busybox sh`, etc.)
*   `coreutils`
*   `gawk` or `busybox awk`

## Installation

Simply source the `mproc.sh` file in your script:

```sh
#!/bin/sh
. ./mproc.sh
```

## Basic Usage

### 1. Define the Worker Function

You must define a function named `mproc_process` to handle the tasks. The library provides two variables for you:

*   `$mproc_number`: The ID of the current worker (1-indexed).
*   `$mproc_message`: The argument passed via `mproc_dispatch`.

```sh
mproc_process() {
  # Example: Compress a file
  # gzip -c "${mproc_message}" > "${mproc_message}.gz"
  printf "Worker %s: Processing %s\n" "${mproc_number}" "${mproc_message}"
}
```

### 2. Create Process Pool

Initialize the pool with a specified number of workers.

```sh
# Create 3 parallel workers
mproc_create 3
```

### 3. Dispatch Tasks

Send tasks to the pool. `mproc_dispatch` blocks until a worker is available, so you can simply run it in a loop.

```sh
for file in *.txt; do
  mproc_dispatch "${file}"
done
```

### 4. Destroy Process Pool

Wait for all tasks to finish and clean up resources.

```sh
mproc_destroy
```

## Using the Progress Bar

The library includes a built-in progress bar.

*   **Initialize**: `mproc_progress <total>` (Sets the total number of tasks).
*   **Tick**: `mproc_progress tick` (Increments progress by 1).
*   **Refresh**: `mproc_progress reprint` (Forces a redraw without changing count).
*   **Abort**: `mproc_progress abort` (Stops with error).

```sh
#!/bin/sh

. ./mproc.sh

mproc_process() {
  sleep 0.5

  # Update progress
  mproc_progress tick
}

mproc_create 3

# Tell progress bar we have 10 tasks
mproc_progress 10

i="1"
while [ "${i}" -le 10 ]; do
  mproc_dispatch "Task-${i}"

  i="$((i + 1))"
done

mproc_destroy
```
