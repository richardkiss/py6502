#!/usr/bin/env python
import time

import termbox

eventdict = {}
with termbox.Termbox() as tb:
    finish = False
    while not finish:
        event = tb.poll_event()
        (type, ch, key, mod, w, h, x, y) = event
        if type == termbox.EVENT_KEY and ch == "X":
            break

        if event in eventdict:
            eventdict[event] += 1
        else:
            eventdict[event] = 1
        time.sleep(0.01)  # Remove this delay to make it not fail.

for e in eventdict:
    print(e, ":", eventdict[e])
