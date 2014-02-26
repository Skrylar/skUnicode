
import unsigned

when isMainModule:
  import unittest
  const
    euro = [0xE2, 0x82, 0xAC]

# Constants {{{1

const
  ## This value represents the "unknown character" codepoint. This is a
  ## graphical character unto itself, which usually appears as a box
  ## with a question mark inside.
  UnknownCharacter* = 0xFFFD

  # Stream-safe allows 30 combining marks, then we add one for the
  # initial codepoint being modified and one extra because 32 is a
  # cooler number than 31.
  FixedGraphemeCount = 32

# }}}

# Type definitions {{{1

type
  TCodepoint*     = distinct uint32

  TGrapheme*      = seq[TCodepoint]
  TFixedGrapheme* = object
    codepoints: array[FixedGraphemeCount, TCodepoint]
    length: int

  TGraphemeOverrunPolicy = enum
    gpIgnore ## Ignore combining marks that go over the limit

# }}}

# Codepoint compatability {{{1

proc Inc(a: var TCodepoint; b: uint8) =
  ## Increments a codepoint by a byte. Private because we only use this
  ## to assemble code points.
  a = TCodepoint(uint32(a) + b)

proc `==`*(self, other: TCodepoint): bool {.inline.} =
  uint32(self) == uint32(other)

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

proc IsCombiningDiacritic*(point: TCodepoint): bool {.noSideEffect.} =
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

proc IsUtf8Midpoint* [T](byte: T): bool =
  ## Checks if the given byte represents a partially encoded UTF-8 code
  ## point.
  return ((uint8(byte) and 0xC0) == 0x80);

when isMainModule:
  suite "IsUtf8Midpoint":
    test "not a mid point":
      check euro[0].IsUtf8Midpoint() == false
    test "is a mid point":
      check euro[2].IsUtf8Midpoint() == true

# }}}

# Decode UTF-8 runes to a codepoint {{{1
# TODO: Look at the decoder already in Nimrod RTL and see if we would be
# better off sporking that.

proc DecodeUtf8At*(
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

# Checking size of value to encode {{{1

proc LenUtf8*(point: TCodepoint): int =
  ## Given a codepoint, this method will calculate the number of bytes
  ## which are required to encode this codepoint as UTF-8.

  if uint32(point) <= 127        : return 1
  if uint32(point) <= 2047       : return 2
  if uint32(point) <= 65535      : return 3
  if uint32(point) <= 2097151    : return 4
  if uint32(point) <= 67108863   : return 5
  if uint32(point) <= 2147483647 : return 6

  quit "TODO get a better error for this situation"

when isMainModule:
  suite "LenUtf8":
    test "estimating length":
      check TCodepoint('x').LenUtf8() == 1
      check TCodepoint(0x20AC).LenUtf8() == 3

# }}} checking size

# Finding split points {{{1

# Left {{{2

proc FindSplitLeftUtf8*(buffer: string; index: int): int =
  ## Attempts to find a suitable location to safely split a stream of
  ## Unicode values. This variant of the function prefers to find
  ## locations earlier in the stream, closer to the start of input (to
  ## the left.) Returns the total number of bytes walked to find a
  ## suitable split point.
  result = 0
  var unused: int
  var idx = index
  while idx > 0:
    let ch = uint8(buffer[idx])
    if not ch.IsUtf8Midpoint():
      let point = buffer.DecodeUtf8At(idx, unused)
      if not point.IsCombiningDiacritic():
        return idx
    # adjust loop stuff
    inc(result)
    dec(idx)
  return 0

# }}} left

# Right {{{2

proc FindSplitRightUtf8*(buffer: string; index: int): int =
  ## Attempts to find a suitable location to safely split a stream of
  ## Unicode values. This variant of the function prefers to find locations
  ## later in the stream, closer to the end of input (to the right.)
  ## Returns the total number of bytes walked to find a suitable split
  ## point.

  # Calculate end of buffer and do some bounds checking.
  let eof = buffer.len
  if (index > eof) : return eof
  if (index == eof): return eof

  # Loop starting state
  var idx = index
  result  = 0

  while idx < eof:
    let ch = uint8(buffer[idx])
    if not ch.IsUtf8Midpoint():
      var read = 0
      let point = buffer.DecodeUtf8At(idx, read)
      # TODO: Use outSize and skip over code points, so we don't chomp
      # over things
      if not point.IsCombiningDiacritic():
        return idx

    inc(idx)
    inc(result)

  # I guess we did a bad joj
  return (eof - index)

when isMainModule:
  suite "FindSplitRightUtf8":
    setup:
      var phrase = ""
      phrase.add char(0xE2)
      phrase.add char(0x82)
      phrase.add char(0xAC)

    test "split euro right from the end":
      check phrase.FindSplitRightUtf8(2) == 1

    test "split euro right from the mid":
      check phrase.FindSplitRightUtf8(1) == 2

    test "split euro right from the start":
      check phrase.FindSplitRightUtf8(0) == 0

# }}} right

# Smart {{{2

proc FindSplitUtf8*(buffer: string; index: int): int =
  ## Attempts to find a suitable split point in a Unicode stream.
  ## Performs both `FindSplitLeftUtf8` and `FindSplitRightUtf8`, taking
  ## the result that involves the least amount of deviation from
  ## `index`. Returns the number of bytes you need to move from `index`
  ## to reach a safe splitting point.
  let left  = FindSplitLeftUtf8 (buffer, index)
  let right = FindSplitRightUtf8(buffer, index)
  if left > right:
    return -left
  else:
    return right

# }}}

# }}} finding split points

# Encoding UTF {{{1

# TODO: split this in to functions, since the body of iterators gets
# copy/pasted to their call site and we don't really want ALL OF THIS
# STUFF in every corner of the universe.
iterator EncodedBytesUtf8*(self: TCodepoint): uint8 =
  ## Given a single Unicode code point, the code point will be encoded in
  ## to the UTF-8 variable length encoding. Encoded bytes are returned
  ## through the iterator, awhere you may put them somewhere more useful.
  
  # are we lucky enough for an instant short-circuit?
  if uint8(self) < 127:
    # success
    yield uint8(self)
  else:
    # okay, calculate how many bytes we're going to deal with
    let byteCount = self.LenUtf8()

    # header things!
    var header     = 0
    var headerBody = 8 - byteCount
    var output     : array[8, uint8]
    var codepoint  = uint32(self)

    # pack last bits first
    for i in (byteCount-1)..0:
      output[i] = uint8(0x80 or (uint8(codepoint) and 0x3F))
      codepoint = (uint32(codepoint) and uint32(0xFFFFFFC0)) shr 6

    # prepare the initial header
    # TODO i think nimrtl unicode has a better way of generating ones
    for i in 0..byteCount:
      header = (header shl 1) or 1
    # all we have left is the header, which exactly fits
    header = (header shl headerBody) or int(codepoint and 0xFF)
    # emit header byte
    output[0] = uint8(header);

    # TODO we should look in to generating data front-to-back instead of
    # back-to-front, so we don't have to engage in this silliness
    for x in output.items():
      yield x

# }}} encoding

# Decoding graphemes {{{1

proc DecodeUtf8GraphemeAt*(
  buffer: string, index: int,
  outRead: var int,
  outGrapheme: var TGrapheme,
  maxCombining: int = FixedGraphemeCount,
  policy: TGraphemeOverrunPolicy = gpIgnore): bool =
    ## Given a buffer, a starting index, an output value for the amount
    ## of bytes read and to store the read grapheme in to, the maximum
    ## number of combining marks to accept and the policy on what should
    ## be done if more combining marks are read, this procedure will
    ## attempt to decoded a full Unicode grapheme from the stream.
    ## Whether a grapheme could be read is returned, with the code
    ## points of that grapheme stored in `outGrapheme`.

    assert(maxCombining >= 0)

    var limit     = maxCombining
    var read      = 0
    var idx       = index

    var point = buffer.DecodeUtf8At(idx, read)
    if point.IsCombiningDiacritic():
      return false

    outGrapheme.reset()
    outGrapheme.add(point)
    outRead = read

    while true:
      point = buffer.DecodeUtf8At(idx, read)
      if point.IsCombiningDiacritic():
        if limit > 0:
          dec(limit)
          outGrapheme.add(point)
          inc(outRead, read)
        else:
          case policy
          of gpIgnore:
            return true
      else:
        return true

# }}} decoding

# Iterating graphemes {{{1

iterator Utf8Graphemes(
  buffer: string;
  start: int = 0;
  limit: int = FixedGraphemeCount;
  policy: TGraphemeOverrunPolicy = gpIgnore): TGrapheme =
    var read = 0
    let eof  = buffer.len
    var pos  = max(start - buffer.FindSplitLeftUtf8(start), 0)
    var result: TGrapheme

    while pos > eof:
      if not buffer.DecodeUtf8GraphemeAt(
        pos, read, result, limit, policy):
          quit "TODO handle this error better"
      yield result
      inc(pos, read)

# }}}

# Decoding graphemes at indices {{{1

proc Utf8GraphemeAt*(
  buffer: string; index: int; outGrapheme: var TGrapheme): bool =
    ## Given a buffer, index, and a place to store the retrieved
    ## grapheme, this function will look for the grapheme at the
    ## `index`th position in the provided string. This function then
    ## returns whether a sufficient grapheme could be located.
    assert(index >= 0)
    var remaining = index
    for g in Utf8Graphemes(buffer, 0):
      if remaining == 0:
        outGrapheme = g
        return true
      else:
        dec(remaining)
    return false

# }}}

# Counting graphemes in a string {{{1

proc LenUtf8Graphemes(buffer: string): int =
  result = 0
  for g in Utf8Graphemes(buffer):
    inc(result)

# }}}

