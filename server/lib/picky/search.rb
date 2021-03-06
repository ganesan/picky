# = Picky Queries
#
# A Picky Search is an object which:
# * holds one or more indexes
# * offers an interface to query these indexes.
#
# You connect URL paths to indexes via a Query.
#
# We recommend not to use this directly, but connect it to an URL and query through one of these
# (Protip: Use "curl 'localhost:8080/query/path?query=exampletext')" in a Terminal.
#
class Search

  include Helpers::Measuring

  attr_reader   :indexes
  attr_writer   :tokenizer, :identifiers_to_remove
  attr_accessor :reduce_to_amount, :weights

  # Takes:
  # * A number of indexes
  # * Options hash (optional) with:
  #   * tokenizer: Tokenizers::Query.default by default.
  #   * weights:   A hash of weights, or a Query::Weights object.
  #
  def initialize *index_definitions
    options      = Hash === index_definitions.last ? index_definitions.pop : {}

    @indexes     = Internals::Query::Indexes.new *index_definitions, combinations_type_for(index_definitions)
    @tokenizer   = options[:tokenizer] || Internals::Tokenizers::Query.default
    weights      = options[:weights] || Query::Weights.new
    @weights     = Hash === weights ? Query::Weights.new(weights) : weights
  end

  # Returns the right combinations strategy for
  # a number of query indexes.
  #
  # Currently it isn't possible using Memory and Redis etc.
  # indexes in the same query index group.
  #
  # Picky will raise a Query::Indexes::DifferentTypesError.
  #
  @@mapping = {
    Index::Memory => Internals::Query::Combinations::Memory,
    Index::Redis  => Internals::Query::Combinations::Redis
  }
  def combinations_type_for index_definitions_ary
    index_types = index_definitions_ary.map(&:class)
    index_types.uniq!
    raise_different(index_types) if index_types.size > 1
    !index_types.empty? && @@mapping[*index_types] || Internals::Query::Combinations::Memory
  end
  # Currently it isn't possible using Memory and Redis etc.
  # indexes in the same query index group.
  #
  class DifferentTypesError < StandardError
    def initialize types
      @types = types
    end
    def to_s
      "Currently it isn't possible to mix #{@types.join(" and ")} Indexes in the same Search instance."
    end
  end
  def raise_different index_types
    raise DifferentTypesError.new(index_types)
  end

  # This is the main entry point for a query.
  # Use this in specs and also for running queries.
  #
  # Parameters:
  # * text: The search text.
  # * ids = 20: _optional_ The amount of ids to calculate (with offset).
  # * offset = 0: _optional_ The offset from which position to return the ids. Useful for pagination.
  #
  # Note: The Rack adapter calls this method after unravelling the HTTP request.
  #
  def search_with_text text, ids = 20, offset = 0
    search tokenized(text), ids, offset
  end

  # Runs the actual search using Query::Tokens.
  #
  # Note: Internal method, use #search_with_text.
  #
  def search tokens, ids = 20, offset = 0
    results = nil

    duration = timed do
      results = execute tokens, ids, offset
    end
    results.duration = duration.round 6

    results
  end

  # Execute a search using Query::Tokens.
  #
  # Note: Internal method, use #search_with_text.
  #
  def execute tokens, ids, offset
    Results.from ids, offset, sorted_allocations(tokens)
  end

  # Delegates the tokenizing to the query tokenizer.
  #
  # Parameters:
  # * text: The text to tokenize.
  #
  def tokenized text
    @tokenizer.tokenize text
  end

  # Gets sorted allocations for the tokens.
  #
  # This generates the possible allocations, sorted.
  #
  # TODO Smallify.
  #
  # TODO Rename: allocations
  #
  def sorted_allocations tokens # :nodoc:
    # Get the allocations.
    #
    # TODO Pass in reduce_to_amount (aka max_allocations)
    #
    # TODO uniq, score, sort in there
    #
    allocations = @indexes.allocations_for tokens

    # Callbacks.
    #
    # TODO Reduce before sort?
    #
    reduce allocations
    remove_from allocations

    # Remove double allocations.
    #
    allocations.uniq

    # Score the allocations using weights as bias.
    #
    allocations.calculate_score weights

    # Sort the allocations.
    # (allocations are sorted according to score, highest to lowest)
    #
    allocations.sort

    # Return the allocations.
    #
    allocations
  end
  def reduce allocations # :nodoc:
    allocations.reduce_to reduce_to_amount if reduce_to_amount
  end

  #
  #
  def remove_from allocations # :nodoc:
    allocations.remove identifiers_to_remove
  end
  #
  #
  def identifiers_to_remove # :nodoc:
    @identifiers_to_remove ||= []
  end

  # Display some nice information for the user.
  #
  def to_s
    s = "#{self.class}("
    s << @indexes.indexes.map(&:name).join(', ')
    s << ", weights: #{@weights}" unless @weights.empty?
    s << ")"
    s
  end

end