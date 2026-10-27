#!/bin/bash
#
# The pty probe, run WITHOUT a controlling terminal — which is how a terminal application is started.
#
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
#
# **THE CONTEXT IS THE TEST.** `NSTask` opened the pty's slave without `O_NOCTTY`. When the opener already has a
# controlling terminal — every run from a shell — that flag changes nothing, so the suite passed. When it does not — a
# session manager, `setsid`, a service, which is how a terminal application is started — the `open` gave the PARENT
# the pty as its own controlling terminal, the child's `TIOCSCTTY` (which does not steal) then had nothing to take, and
# the shell came up with no job control: MEASURED as `bash: cannot set terminal process group (-1)` in the terminal
# application while this very probe passed. So it runs under `setsid`, in the shape that broke.
set -u

BINARY="${1:?usage: run-nstask-pseudoterminal.sh BINARY}"
exec setsid -w "$BINARY"
