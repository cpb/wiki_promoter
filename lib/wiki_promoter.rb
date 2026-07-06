# frozen_string_literal: true

require_relative "wiki_promoter/version"
require_relative "wiki_promoter/migrator"
require_relative "wiki_promoter/publisher"

module WikiPromoter
  class Error < StandardError; end
end
