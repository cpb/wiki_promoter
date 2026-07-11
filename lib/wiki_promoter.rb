# frozen_string_literal: true

require_relative "wiki_promoter/version"
require_relative "wiki_promoter/migrator"
require_relative "wiki_promoter/publisher"

module WikiPromoter
  class Error < StandardError; end

  # Percent-encode a wiki page name for use as a markdown link target.
  # GitHub wiki renders [text](page name) as plain text when the URL
  # contains unencoded reserved characters: '#' starts a fragment, '%'
  # creates invalid escape sequences, '(' ')' break the markdown link
  # syntax. Encode '%' first to avoid double-encoding.
  def self.encode_wiki_link_target(wiki_name)
    wiki_name
      .gsub("%", "%25")
      .gsub(" ", "%20")
      .gsub("#", "%23")
      .gsub("(", "%28")
      .gsub(")", "%29")
  end
end
