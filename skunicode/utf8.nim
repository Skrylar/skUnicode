
when isMainModule:
  import unittest
  const
    euro = [0xE2, 0x82, 0xAC]

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
  outRead: var int,
  policy: InvaildUnicodePolicy = iuReturnUnknown): Codepoint =
    ## Performs decoding on a given string to read a single Unicode code
    ## point from that buffer.  The number of bytes which were consumed
    ## to read the codepoint is stored in the `outRead` parameter.

    let eof    = buffer.len
    var toRead = 0
    var here   = index
    result     = Codepoint(0)
    outRead    = 0

    block doGoodJob:
      # check if we were just asked to decode a middle mark
      var ch = uint8(buffer[index])
      if (ch and 0xC0) == 0x80:
        break doGoodJob
        
      # check if this is a single-byte letter
      if (ch and 0x80) == 0:
        outRead = 1
        return Codepoint(ch)
      elif (ch and 0xE0) == 0xC0:
        # check if this is a two-byte letter
        if (index + 1) > eof: break doGoodJob
        result = Codepoint((not uint8(0xE0)) and ch)
        toRead = 1
      elif (ch and 0xF0) == 0xE0:
        # check if this is a three-byte letter
        if (index + 2) > eof: break doGoodJob
        result = Codepoint((not uint8(0xF0)) and ch)
        toRead = 2
      elif (ch and 0xF8) == 0xF0:
        # check if this is a four-byte letter
        if (index + 3) > eof: break doGoodJob
        result = Codepoint((not uint8(0xF8)) and ch)
        toRead = 3
      elif (ch and 0xFC) == 0xF8:
        # check if this is a five-byte letter
        if (index + 4) > eof: break doGoodJob
        result = Codepoint((not uint8(0xFC)) and ch)
        toRead = 4
      elif (ch and 0xFE) == 0xFC:
        # check if this is a six-byte letter
        if (index + 5) > eof: break doGoodJob
        result = Codepoint((not uint8(0xFE)) and ch)
        toRead = 5

      outRead = toRead + 1

      # we read the header, that counts as one byte
      inc(here)
      while toRead > 0:
        let ch = buffer[here]
        result = Codepoint((uint32(result) shl 6) + (uint8(ch) and uint8(0x3F)))
        inc(here)
        dec(toRead)
      return result

    # breaking here means sadness occurred
    case policy
      of iuReturnUnknown:
        outRead = 1
        return Codepoint(UnknownCharacter)

when isMainModule:
  suite "DecodeUtf8At":
    setup:
      var phrase: string = ""
      phrase.add 'f'
      phrase.add 'i'
      phrase.add char(0xE2)
      phrase.add char(0x82)
      phrase.add char(0xAC)
      phrase.add '9'

    test "correct read counts":
      var pos = 0
      var readBytes = 0

      checkpoint "first letter"
      var ret = DecodeUtf8At(phrase, pos, readBytes)
      check ret == Codepoint('f')
      check readBytes == 1

      checkpoint "second letter"
      inc(pos, readBytes)
      check pos == 1
      ret = DecodeUtf8At(phrase, pos, readBytes)
      check ret == Codepoint('i')
      check readBytes == 1

      checkpoint "third letter"
      inc(pos, readBytes)
      check pos == 2
      ret = DecodeUtf8At(phrase, pos, readBytes)
      check ret == Codepoint(0x20AC)
      check readBytes == 3

      checkpoint "fourth letter"
      inc(pos, readBytes)
      check pos == 5
      ret = DecodeUtf8At(phrase, pos, readBytes)
      check ret == Codepoint('9')
      check readBytes == 1

# }}} decode

# Checking size of value to encode {{{1

# Codepoints {{{2

proc LenUtf8*(point: Codepoint): int =
  ## Given a codepoint, this method will calculate the number of bytes
  ## which are required to encode this codepoint as UTF-8.

  if uint32(point)   <= 127        : return 1
  elif uint32(point) <= 2047       : return 2
  elif uint32(point) <= 65535      : return 3
  elif uint32(point) <= 2097151    : return 4
  elif uint32(point) <= 67108863   : return 5
  elif uint32(point) <= 2147483647 : return 6

  quit "TODO get a better error for this situation"

when isMainModule:
  suite "LenUtf8":
    test "estimating length":
      check Codepoint('x').LenUtf8() == 1
      check Codepoint(0x20AC).LenUtf8() == 3

# }}} codepoints

# Graphemes {{{2

proc LenUtf8*(point: Grapheme): int =
  result = 0
  for cp in items(point):
    inc result, LenUtf8(cp)

# }}}

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
        return result
    # adjust loop stuff
    inc(result)
    dec(idx)
  return index

when isMainModule:
  suite "FindSplitLeftUtf8":
    setup:
      var phrase = ""
      phrase.add char(0xE2)
      phrase.add char(0x82)
      phrase.add char(0xAC)

    test "split euro left from the end":
      check phrase.FindSplitLeftUtf8(2) == 2
      
    test "split euro left from the start":
      check phrase.FindSplitLeftUtf8(0) == 0

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
iterator EncodedBytesUtf8*(self: Codepoint): uint8 =
  ## Given a single Unicode code point, the code point will be encoded in
  ## to the UTF-8 variable length encoding. Encoded bytes are returned
  ## through the iterator, awhere you may put them somewhere more useful.
  
  # are we lucky enough for an instant short-circuit?
  if uint32(self) <= 127:
    # success
    # XXX doing this as uint8(uint32(...)) crashes the compiler
    var a = uint32(self)
    var b = uint8(a)
    yield b
  else:
    # okay, calculate how many bytes we're going to deal with
    var byteCount = self.LenUtf8()
    let buffer = uint32(self)
    # generate a header
    case byteCount
    of 2:
     yield uint8(0xC0) + uint8(buffer shr 6)
     yield uint8(0x80) + uint8((buffer and 0x3F))
    of 3:
     yield uint8(0xE0) + uint8(buffer shr 12)
     yield uint8(0x80) + uint8((buffer shr 6) and 0x3F)
     yield uint8(0x80) + uint8((buffer and 0x3F))
    of 4:
     yield uint8(0xF0) + uint8(buffer shr 18)
     yield uint8(0x80) + uint8((buffer shr 12) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 6) and 0x3F)
     yield uint8(0x80) + uint8((buffer and 0x3F))
    of 5:
     yield uint8(0xF8) + uint8(buffer shr 24)
     yield uint8(0x80) + uint8((buffer shr 18) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 12) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 6) and 0x3F)
     yield uint8(0x80) + uint8((buffer and 0x3F))
    of 6:
     yield uint8(0xFC) + uint8(buffer shr 30)
     yield uint8(0x80) + uint8((buffer shr 24) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 18) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 12) and 0x3F)
     yield uint8(0x80) + uint8((buffer shr 6) and 0x3F)
     yield uint8(0x80) + uint8((buffer and 0x3F))
    else:
     quit "TODO this is an invalid size"

when isMainModule:
  suite "EncodedBytesUtf8":
    test "single byte encoding":
      var count = 0
      for b in Codepoint('S').EncodedBytesUtf8():
        check b == uint8('S')
        inc(count)
      check count == 1

    test "multi-byte encoding":
      var count = 0
      for b in Codepoint(0x20AC).EncodedBytesUtf8():
        check uint8(euro[count]) == b
        inc(count)
      check count == 3

# }}} encoding

# Decoding graphemes {{{1

proc DecodeUtf8GraphemeAt*(
  buffer: string, index: int,
  outRead: var int,
  outGrapheme: var Grapheme,
  maxCombining: int = FixedGraphemeCount,
  policy: GraphemeOverrunPolicy = gpIgnore): bool =
    ## Given a buffer, a starting index, an output value for the amount
    ## of bytes read and to store the read grapheme in to, the maximum
    ## number of combining marks to accept and the policy on what should
    ## be done if more combining marks are read, this procedure will
    ## attempt to decoded a full Unicode grapheme from the stream.
    ## Whether a grapheme could be read is returned, with the code
    ## points of that grapheme stored in `outGrapheme`.

    assert(maxCombining >= 0)

    let eof   = buffer.len
    var limit = maxCombining
    var read  = 0
    var idx   = index
    var point = buffer.DecodeUtf8At(idx, read)

    if point.IsCombiningDiacritic():
      return false

    outGrapheme.setLen(1)
    outGrapheme[0] = point
    outRead = read
    inc(idx, read)

    while idx <= eof:
      # TODO check if we just ran in to a midpoint
      point = buffer.DecodeUtf8At(idx, read)
      if point.IsCombiningDiacritic():
        if limit > 0:
          dec(limit)
          outGrapheme.add(point)
        else:
          case policy
          of gpIgnore: discard # Okay, we'll just ignore more things.
        inc(outRead, read)
      else:
        return true
    return false

# }}} decoding

# Iterating graphemes {{{1

iterator Utf8GraphemesSliced*(
  start, ending: int; # in bytes!
  buffer: string;
  limit: int = FixedGraphemeCount;
  policy: GraphemeOverrunPolicy = gpIgnore): Grapheme =
    assert start >= 0
    assert ending <= buffer.len
    var read = 0
    var pos  = start
    var result: Grapheme = @[]
    block joj:
      while pos < ending:
        if not buffer.DecodeUtf8GraphemeAt(
          pos, read, result, limit, policy):
            break joj # we did whatever it took to get the joj
        yield result
        inc(pos, read)

iterator Utf8Graphemes*(
  buffer: string;
  limit: int = FixedGraphemeCount;
  policy: GraphemeOverrunPolicy = gpIgnore): Grapheme =
    for x in Utf8GraphemesSliced(0, buffer.len, buffer, limit, policy):
      yield x

# }}}

# Decoding graphemes at indices {{{1

proc Utf8GraphemeAt*(
  buffer: string; index: int; outGrapheme: var Grapheme): bool =
    ## Given a buffer, index, and a place to store the retrieved
    ## grapheme, this function will look for the grapheme at the
    ## "index"th position in the provided string. This function then
    ## returns whether a sufficient grapheme could be located.
    assert(index >= 0)
    var remaining = index
    for g in Utf8Graphemes(buffer):
      if remaining == 0:
        outGrapheme = g
        return true
      else:
        dec(remaining)
    return false

when isMainModule:
  suite "Utf8GraphemeAt":
    setup:
      var phrase: string = ""
      phrase.add 'f'
      phrase.add 'i'
      phrase.add char(0xE2)
      phrase.add char(0x82)
      phrase.add char(0xAC)
      phrase.add '9'

    test "indexing graphemes":
      var outGrapheme: Grapheme = @[]

      checkpoint "first grapheme"
      var ret = Utf8GraphemeAt(phrase, 0, outGrapheme)
      check ret == true
      check outGrapheme.len == 1
      check outGrapheme[0] == 'f'

      checkpoint "second grapheme"
      ret = Utf8GraphemeAt(phrase, 1, outGrapheme)
      check ret == true
      check outGrapheme.len == 1
      check outGrapheme[0] == 'i'

      checkpoint "third grapheme"
      ret = Utf8GraphemeAt(phrase, 2, outGrapheme)
      check ret == true
      check outGrapheme.len == 1
      check outGrapheme[0] == Codepoint(0x20AC)

      checkpoint "fourth grapheme"
      ret = Utf8GraphemeAt(phrase, 3, outGrapheme)
      check ret == true
      check outGrapheme.len == 1
      check outGrapheme[0] == '9'

      # TODO: test a grapheme with combining marks attached

# }}}

# Counting graphemes in a string {{{1

proc LenUtf8Graphemes*(buffer: string): int =
  result = 0
  for g in Utf8Graphemes(buffer):
    inc(result)

when isMainModule:
  suite "LenUtf8Graphemes":
    setup:
      var phrase: string = ""
      phrase.add 'f'
      phrase.add 'i'
      phrase.add char(0xE2)
      phrase.add char(0x82)
      phrase.add char(0xAC)
      phrase.add '9'

    test "counting the graphemes":
      check phrase.LenUtf8Graphemes() == 4

# }}}

