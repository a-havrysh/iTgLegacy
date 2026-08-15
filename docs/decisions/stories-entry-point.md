# Stories: visibility and entry point

Decided by the owner after using the app on the device.

## The tray is conditional, not permanent

The stories row above the chat list appears only when there are stories to show.
No stories means no row, no reserved space, no empty "My Story" placeholder.
The list starts at the first chat.

Today the row is always present and carries a "+ My Story" tile, which spends
82 points of a 480 point screen on an affordance most people will use rarely.

## Posting moves to the compose button

The compose button in the top right of the chat list no longer opens a new
message directly. It opens a short menu:

    New Message
    Add Story

Choosing New Message does exactly what tapping compose does today, so the
common path costs one extra tap and nothing else. Choosing Add Story opens the
story composer.

## Why this shape

It separates how often something is used from how reachable it is. Posting a
story stays one gesture away at all times, including when nobody you follow has
posted anything, which is precisely when a permanent tray would be showing an
empty strip. And the chat list gets its vertical space back.

The menu itself follows the original's own menu component, not an invented one.
