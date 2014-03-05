
# Combining Diacritic Marks {{{1
# http://en.wikipedia.org/wiki/Combining_character
#
# Combining Diacritical Marks (0300–036F), since version 1.0, with
# modifications in subsequent versions down to 4.1
#
# Combining Diacritical Marks Supplement (1DC0–1DFF), versions 4.1 to
# 5.2
#
# Combining Diacritical Marks for Symbols (20D0–20FF), since version
# 1.0, with modifications in subsequent versions down to 5.1
#
# Combining Half Marks (FE20–FE2F), versions 1.0, updates in 5.2

proc IsCombiningDiacritic*(point: Codepoint): bool {.noSideEffect.} =
  ## Checks if the given code point represents a combining diacritic
  ## mark. Does not require the unicode character database.
  if (uint32(point) >= uint32(0x0300)) and
    (uint32(point) <= uint32(0x036F)): return true
  if (uint32(point) >= uint32(0x1DC0)) and
    (uint32(point) <= uint32(0x1DFF)): return true
  if (uint32(point) >= uint32(0x20D0)) and
    (uint32(point) <= uint32(0x20FF)): return true
  if (uint32(point) >= uint32(0xFE20)) and
    (uint32(point) <= uint32(0xFE2F)): return true
  return false

# }}} combining marks

