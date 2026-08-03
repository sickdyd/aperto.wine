require "strscan"

module WineReferences
  # The X-Wines CSV stores repeated columns as Python literal lists —
  # `['Merlot', 'Syrah']`, `[2020, 2019]`, `[2021, 'N.V.']`. They are not JSON
  # (single quotes), so JSON.parse cannot read them and `eval` is never an
  # option on third-party data. This is a deliberately small, total scanner:
  # it never raises, and returns the elements as strings.
  module PythonList
    QUOTED = /'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/
    SEPARATOR = /[\s,]+/
    BARE = /[^,]+/
    # pandas writes a missing cell as a bare `nan` (or `None`) rather than an
    # empty string, so an unbracketed null token means "no list", not a
    # one-element list holding the word "nan". Quoted elements inside a real
    # list (`['nan']`) are left alone.
    NULL_TOKEN = /\A(?:nan|none)\z/i

    module_function

    def parse(value)
      raw = value.to_s.strip
      return [] if raw.match?(NULL_TOKEN)

      scanner = StringScanner.new(unwrap(raw))
      elements = []

      until scanner.eos?
        scanner.skip(SEPARATOR)
        break if scanner.eos?

        element = scan_element(scanner)
        elements << element if element.present?
      end

      elements
    end

    def integers(value)
      parse(value).filter_map { |element| Integer(element, exception: false) }.uniq.sort
    end

    def unwrap(raw)
      return raw[1..-2].to_s if raw.start_with?("[") && raw.end_with?("]")

      raw
    end
    private_class_method :unwrap

    def scan_element(scanner)
      quoted = scanner.scan(QUOTED)
      return unescape(quoted[1..-2].to_s) if quoted

      scanner.scan(BARE).to_s.strip
    end
    private_class_method :scan_element

    def unescape(element)
      element.gsub(/\\(.)/) { Regexp.last_match(1) }
    end
    private_class_method :unescape
  end
end
