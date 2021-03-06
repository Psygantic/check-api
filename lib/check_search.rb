class CheckSearch

  def initialize(options)
    # options include keywords, projects, tags, status
    options = JSON.parse(options)
    @options = options.clone
    @options['input'] = options.clone
    @options['team_id'] = Team.current.id unless Team.current.nil?
    # set sort options
    @options['sort'] ||= 'recent_added'
    @options['sort_type'] ||= 'desc'
    # set show options
    @options['show'] = prepare_show_filter(@options['show'])
  end

  def pusher_channel
    if @options['parent'] && @options['parent']['type'] == 'project'
      Project.find(@options['parent']['id']).pusher_channel
    else
      nil
    end
  end

  def id
    CheckSearch.id(@options['input'])
  end

  def self.id(options = {})
    Base64.encode64("CheckSearch/#{options.to_json}")
  end

  def class_name
    'CheckSearch'
  end

  def medias
    return [] if @options['show'] == ['source']
    if should_hit_elasticsearch?('medias')
      query = medias_build_search_query
      ids = medias_get_search_result(query).map(&:annotated_id)
      items = ProjectMedia.where(id: ids).eager_load(:media)
      sort_es_items(items, ids)
    else
      results = ProjectMedia.eager_load(:media).joins(:project)
      sort_pg_results(results)
    end
  end

  def project_medias
    medias
  end

  def sources
    return [] unless @options['show'].include?('source')
    if should_hit_elasticsearch?('sources')
      query = medias_build_search_query('ProjectSource')
      ids = medias_get_search_result(query).map(&:annotated_id)
      items = ProjectSource.where(id: ids).eager_load(:source)
      sort_es_items(items, ids)
    else
      results = ProjectSource.eager_load(:source).joins(:project)
      sort_pg_results(results)
    end
  end

  def project_sources
    sources
  end

  def number_of_results
    # TODO cache `medias` and `sources` results?
    medias.count + sources.count
  end

  private

  def should_hit_elasticsearch?(type)
    !(@options['status'].blank? && @options['tags'].blank? && @options['keyword'].blank? && show_filter?(type))
  end

  def show_filter?(type)
    # show filter should not include all media types to hit ES
    show_options = type == 'medias' ? ['uploadedimage', 'link', 'claim'] : ['source']
    (@options['show'].sort == show_options.sort && (@options['show'] - show_options).empty?)
  end

  def medias_build_search_query(associated_type = 'ProjectMedia')
    conditions = []
    conditions << {term: { annotated_type: associated_type.downcase } }
    conditions << {term: { team_id: @options["team_id"] } } unless @options["team_id"].nil?
    conditions.concat build_search_keyword_conditions(associated_type)
    conditions.concat build_search_tags_conditions
    conditions.concat build_search_parent_conditions
    { bool: { must: conditions } }
  end

  def build_search_keyword_conditions(associated_type)
    return [] if @options["keyword"].blank?
    # add keyword conditions
    keyword_fields = %w(title description quote account.username account.title)
    keyword_c = [{ query_string: { query: @options["keyword"], fields: keyword_fields, default_operator: "AND" } }]

    [['comment', 'text'], ['dynamic', 'indexable']].each do |pair|
      keyword_c << { has_child: { type: "#{pair[0]}_search", query: { query_string: { query: @options["keyword"], fields: [pair[1]], default_operator: "AND" }}}}
    end

    if associated_type == 'ProjectSource'
      keyword_c << { has_child: { type: "account_search", query: { query_string: { query: @options["keyword"], fields: %w(username title), default_operator: "AND" }}}}
    end
    [{bool: {should: keyword_c}}]
  end

  def build_search_tags_conditions
    return [] if @options["tags"].blank?
    tags_c = []
    tags = @options["tags"].collect{ |t| t.delete('#') }
    tags.each do |tag|
      tags_c << { match: { full_tag: { query: tag, operator: 'and' } } }
    end
    tags_c << { terms: { tag: tags } }
    [{has_child: { type: 'tag_search', query: { bool: {should: tags_c }}}}]
  end

  def build_search_parent_conditions
    parent_c = []
    fields = {'project_id' => 'projects', 'associated_type' => 'show', 'status' => 'status'}
    fields.each do |k, v|
      parent_c << {terms: { "#{k}": @options[v] } } unless @options[v].blank?
    end
    parent_c
  end

  def medias_get_search_result(query)
    field = @options['sort'] == 'recent_activity' ? 'last_activity_at' : 'created_at'
    MediaSearch.search(query: query, sort: [{ field => { order: @options["sort_type"].downcase }}, '_score'], size: 10000).results
  end

  def sort_pg_results(results)
    results = results.where('projects.team_id' => @options['team_id']) unless @options['team_id'].blank?
    results = results.where(project_id: @options['projects']) unless @options['projects'].blank?
    sort_field = @options['sort'].to_s == 'recent_activity' ? 'updated_at' : 'created_at'
    sort_type = @options['sort_type'].blank? ? 'desc' : @options['sort_type'].downcase
    results.order(sort_field => sort_type)
  end

  def sort_es_items(items, ids)
    ids_sort = items.sort_by{|x| ids.index x.id.to_s}
    ids_sort.to_a
  end

  def prepare_show_filter(show)
    m_types = ['photos', 'links', 'quotes']
    show ||= m_types
    if show.include?('medias')
      show.delete('medias')
      show += m_types
    end
    show.map(&:downcase)
    show_mapping = {'photos' => 'uploadedimage', 'links' => 'link', 'quotes' => 'claim', 'sources' => 'source'}
    show.each_with_index do |v, i|
      show[i] = show_mapping[v] unless show_mapping[v].blank?
    end
    show
  end

end
