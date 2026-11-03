# Harness² tool guidance

- After a failed call, name the cause (bad input, timeout, missing capability, permission,
  unread output) and change something before calling again; a hook refuses an identical retry.
- After writing a file a user will look at, check it mechanically (size, dimensions, a test)
  before saying it is done; a successful write does not prove it is right.
