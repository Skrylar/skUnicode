
# Constants {{{1

const
  ## This value represents the "unknown character" codepoint. This is a
  ## graphical character unto itself, which usually appears as a box
  ## with a question mark inside.
  UnknownCharacter* = 0xFFFD

  ## Stream-safe allows 30 combining marks, then we add one for the
  ## initial codepoint being modified and one extra because 32 is a
  ## cooler number than 31.
  FixedGraphemeCount* = 32

# }}}

# Type definitions {{{1

type
  Codepoint*     = distinct uint32

  Grapheme*      = seq[Codepoint]
  FixedGrapheme* = object
    codepoints: array[FixedGraphemeCount, Codepoint]
    length: int

  GraphemeOverrunPolicy* = enum
    gpIgnore ## Ignore combining marks that go over the limit

  InvaildUnicodePolicy* = enum
    iuReturnUnknown

# }}}

# Codepoint compatability {{{1

proc `==`*(self, other: Codepoint): bool {.inline.} =
  uint32(self) == uint32(other)

proc `==`*(self: Codepoint, other: char): bool {.inline.} =
  uint32(self) == uint32(other)

converter toGrapheme*(x: char): Grapheme = @[Codepoint(x)]

# }}}

