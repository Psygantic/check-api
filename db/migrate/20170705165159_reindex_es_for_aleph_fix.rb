class ReindexEsForAlephFix < ActiveRecord::Migration
  def change
    CheckElasticSearchModel.reindex_es_data
  end
end
