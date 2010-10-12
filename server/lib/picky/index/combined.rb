# encoding: utf-8
#
module Index

  # This index combines a full and partial index.
  # It serves to order the results such that exact (full) hits are found first.
  #
  # TODO Rename full -> exact. exact/partial?
  #
  # TODO Need to use the right subtokens. Bake in?
  #
  # TODO One can use it as a wrapper, and it will extract the indexes itself. Rename: ExactFirst.
  #
  class Combined < Bundle
    
    delegate :similar,
             :identifier,
             :name,
             :to => :@full
    delegate :type,
             :category,
             :weight,
             :generate_partial_from,
             :generate_caches_from_memory,
             :generate_derived,
             :dump,
             :load,
             :to => :@partial
    
    # TODO initialize type_or_category # => installs itself on all full and partial
    #
    def initialize full, partial
      @full    = full
      @partial = partial
    end
    
    def ids text
      @full.ids(text) + @partial.ids(text)
    end
    
    def weight text
      [@full.weight(text) || 0, @partial.weight(text) || 0].max
    end
    
  end
  
end