#!/bin/sh
. ./mproc.sh

mproc_process() {
  sleep 0.5
  mproc_printf "${mproc_number}: ${mproc_message}"

  # Update progress
  mproc_progress tick
}

mproc_finish() {
  mproc_printf "Finished!"
}

mproc_create 3

# Tell progress bar we have 10 tasks
mproc_progress 20

i="1"
while [ "${i}" -le 20 ]; do
  mproc_dispatch "Task-${i}"

  i="$((i + 1))"
done

mproc_printf "Destroying... %s" "Duck!"
mproc_destroy
