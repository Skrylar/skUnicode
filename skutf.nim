
import unsigned

when isMainModule:
  import unittest

# Type definitions {{{1

type
  TCodepoint* = distinct uint32

# }}}

# Constants {{{1

const
  ## This value represents the "unknown character" codepoint. This is a
  ## graphical character unto itself, which usually appears as a box
  ## with a question mark inside.
  UnknownCharacter* = 0xFFFD

# }}}

# Codepoint compatability {{{1

proc Inc(a: var TCodepoint; b: uint8) =
  ## Increments a codepoint by a byte. Private because we only use this
  ## to assemble code points.
  a = TCodepoint(uint32(a) + b)

# }}}

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

proc IsCombiningDiacritic(point: TCodepoint): bool {.noSideEffect.} =
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

# }}}

# Midpoint Checking {{{1

proc IsUtf8Midpoint(byte: uint8): bool =
  ## Checks if the given byte represents a partially encoded UTF-8 code
  ## point.
  return ((byte and 0xC0) == 0x80);

# }}}

# Decode UTF-8 runes to a codepoint {{{1
# TODO: Look at the decoder already in Nimrod RTL and see if we would be
# better off sporking that.

proc DecodeUtf8At(
  buffer: string,
  index: int,
  outRead: var int): TCodepoint =
    ## Performs decoding on a given string to read a single Unicode code
    ## point from that buffer.
    ##
    ## The number of bytes which were consumed to read the codepoint is
    ## stored in the `outRead` parameter.
    ##
    ## If an error occurs, U+FFFD is returned. Note that this behavior
    ## is slotted to change in the future, as whether U+FFFD is returned
    ## or an error is raised should be up to the caller.

    # accumulate the code point while its being constructed
    result = TCodepoint(0)
    # artifact of replacing pointer arithmetic with bounded arrays
    var input = index
    # unpack the first character of interest
    var c : uint8 = uint8(buffer[index])
    # sentry for checking encoding length
    var sentry : uint8 = 128
    # mask for extracting bits from first byte
    var mask : uint8 = 0
    # count number of unicode bytes
    var hits: int = 0

    # we haven't read anything yet
    outRead = 0

    # check for a one-rune input; if the input is a one-rune read,
    # we can short circuit out right now
    if (c and 128) == 0:
      outRead = 1
      return TCodepoint(c)

    # calculate the amount of components we need to read
    while (bool((c and sentry) > uint8(0)) and (hits < 7)):
      inc(hits)
      mask = mask or sentry
      sentry = (sentry shr 1)

    # if hit count is invalid, return failure
    if hits > 6:
      # TODO use better fail code
      outRead = 0
      return TCodepoint(UnknownCharacter)

    # shove the header in to place
    inc(result, c and (not mask))
    inc(input)

    # output number of bytes read
    outRead = hits;

    # decode the rest
    let eof = buffer.len
    while hits > 0:
      dec(hits)
      # did we just overrun?
      if input >= eof:
        # TODO use better fail code
        outRead = 0
        return TCodepoint(UnknownCharacter)
      else:
        # decode and accumulate the byte
        c = uint8(buffer[input])
        inc(input)
        # verify the component bytes are flagged
        if (c and 192) != 128:
          # TODO use better fail code
          outRead = 0
          return TCodepoint(UnknownCharacter)
        # accumulate
        result = TCodepoint((uint32(result) shl 6) + (c and 63))
    return result

  # XXX used to have 'goto fail' down here, now we have repeat code;
  # should we make a private template and put the code in there, or
  # should we throw an exception on error and then decide what to return
  # in the 'catch' block?

# }}} decode

