class ErrorUXRound2::UnknownTokenParser
pragma extended
token WORD
rule
document: WORD { result = val[0] }
end
---- inner
def parse(source, file: "(h003-unknown-token)")
  @h003_source = source
  @h003_file = file
  @h003_offset = 0
  do_parse
end

def next_token
  source = @h003_source
  @h003_offset += 1 while source[@h003_offset] == " "
  return false if @h003_offset >= source.bytesize

  start = @h003_offset
  token = if source.getbyte(start) == 64
            @h003_offset += 1
            [:H003_UNKNOWN, "@"]
          else
            finish = start
            finish += 1 while finish < source.bytesize && source.getbyte(finish).between?(97, 122)
            word = source.byteslice(start...finish)
            @h003_offset = finish
            [:WORD, word]
          end
  [*token, {
    file: @h003_file, line: 1, column: start + 1, start_byte: start,
    end_byte: @h003_offset, source_line: source
  }]
end
